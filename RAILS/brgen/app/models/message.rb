# frozen_string_literal: true

class Message < ApplicationRecord
  include Shared::MediaProcessable
  tracks_activity created: "MessageSent", source_vertical: "messages", actor: :sender

  include Shared::Notifiable
  include Shared::Reactable
  belongs_to :conversation
  belongs_to :sender, class_name: "User", foreign_key: :sender_id
  has_many :message_receipts, dependent: :destroy
  # A reply points at what it answers. In a channel with several
  # conversations running at once, a message with no referent is one nobody can
  # follow.
  belongs_to :parent, class_name: "Message", optional: true
  has_many :replies, class_name: "Message", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  # Where a forwarded copy came from. :nullify, because unsending the original
  # must not take the copy with it — the copy is the forwarder's message in
  # someone else's thread, and it is quoting what was said, not linking to it.
  belongs_to :forwarded_from, class_name: "Message", optional: true
  has_many :forwards, class_name: "Message", foreign_key: :forwarded_from_id, dependent: :nullify, inverse_of: :forwarded_from
  has_one_attached :attachment
  process_media_variants :attachment, variants: {
    inline: { resize_to_limit: [ 900, 900 ], format: :webp },
    thumb: { resize_to_limit: [ 320, 320 ], format: :webp }
  }

  # unless deleted?: unsend! empties the body and keeps the row, and without
  # this the record would be permanently invalid — every later save on it, from
  # a receipt or a reaction, would fail.
  #
  # An attachment is also a message. A voice note has no words in it by
  # definition, and requiring some is how a client ends up sending a space.
  validates :content, presence: true, unless: -> { deleted? || attachment.attached? }
  # messages.content is NOT NULL and unsend! already writes "" into it, so a
  # bodyless attachment matches that rather than making the column nullable.
  # A text message with no body still fails the presence rule above.
  before_validation { self.content = "" if content.nil? }
  validates :content, length: { maximum: 10_000 }
  validates :message_type, inclusion: { in: %w[text image file audio] }

  # Live delivery. The declarative `broadcasts_to` re-renders _message inside
  # Turbo's broadcast job (no request), where the reloaded message's belongs_to
  # reads — conversation.channel?, sender.channel_handle — hit the default :all
  # strict-loading mode: development LOGS the violation, test and production
  # RAISE it, so the message saved (200) but never appeared for anyone. Reload
  # with those associations and strict loading off before broadcasting.
  # `targets:` (a CSS selector), not `target:` (one dom id): the corner chat
  # widget lives in the layout, so a channel page has two logs — a selector
  # appends to every open .conversation-log rather than whichever came first.
  after_create_commit :broadcast_to_logs

  # What the link in this message is. Attached on create, filled in off the
  # request, and shared with every other message carrying the same URL.
  belongs_to :link_preview, optional: true

  # The story this message answers, if it is a story reply. The story expires in
  # 24 hours and the reply does not, so the thread keeps the answer after the
  # thing it answered is gone.
  belongs_to :story, optional: true

  after_create :attach_link_preview
  after_create :deliver_receipts
  after_create :clear_typing_indicators
  after_create :schedule_expiration, if: :should_expire?
  after_create_commit :maybe_summon_bot, if: :bot_worthy?

  scope :recent, -> { order(created_at: :desc) }
  # Soft-deleted messages keep their row so a threaded reply is not orphaned,
  # but they carry no body. Every render reads this rather than `all`.
  scope :visible, -> { where(deleted_at: nil) }
  scope :unexpired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired? = expires_at&.past?

  def edited? = edited_at.present?
  def deleted? = deleted_at.present?
  def reply? = parent_id.present?
  def voice? = message_type == "audio"
  def forwarded? = forwarded_from_id.present?

  # A forward carries the body into another thread. Same promise as search: a
  # message that has disappeared or been unsent is gone, so there is nothing to
  # carry.
  def forwardable? = !deleted? && !expired?

  # Editing is bounded: a message that can be rewritten hours later is a
  # message a reader cannot trust, and the receipt they already read is gone.
  EDIT_WINDOW = 15.minutes

  def editable_by?(user)
    user.present? && user.id == sender_id && !deleted? && created_at > EDIT_WINDOW.ago
  end

  # Unsending has no window. A message sent to the wrong room — with a real
  # address in it, on a hyperlocal chat — is a safety problem, not a typo.
  def deletable_by?(user)
    user.present? && user.id == sender_id && !deleted?
  end

  def edit!(new_content)
    update!(content: new_content, edited_at: Time.current)
  end

  # The row stays, the body goes: a hard delete leaves a hole in a thread and
  # orphans whatever replied to it.
  def unsend!
    update_columns(
      content: "", deleted_at: Time.current, updated_at: Time.current
    )
  end

  # Expiry is unsend, not destroy: a hard delete holes a thread and orphans
  # replies (the reason unsend! exists). Attachments go with the body.
  def expire!
    unsend!
    attachment.purge if attachment.attached?
  end

  # Urgency tier for the fading-bubble treatment in the message thread —
  # derived from how much of the message's own lifespan is left, not a
  # fixed clock value, so a 5-minute channel message and a 7-day DM both
  # read as "soon" at the same relative point.
  def expiry_urgency
    return nil unless expires_at

    remaining = expires_at - Time.current
    return "soon" if remaining <= 0
    lifespan = expires_at - created_at
    return "soon" if remaining < lifespan * 0.25
    remaining < lifespan * 0.6 ? "later" : "fresh"
  end

  def should_expire? = expires_at.present? || conversation.disappearing_messages?

  def mark_as_read!(user)
    receipt = message_receipts.find_or_initialize_by(user: user)
    receipt.update!(read_at: Time.current) unless receipt.read_at
  end

  def read_by?(user)
    message_receipts.where(user: user).where.not(read_at: nil).exists?
  end

  # Only human messages in a channel can summon a bot — never a bot replying to
  # a bot (that would loop) and never a plain DM.
  def bot_worthy? = conversation.channel? && !sender.bot?

  def maybe_summon_bot = ChannelBotReplyJob.set(wait: rand(2..6).seconds).perform_later(id)

  private

  def broadcast_to_logs
    fresh = Message.strict_loading(false).includes(:sender, :conversation, :link_preview).find(id)
    fresh.broadcast_append_to(
      conversation,
      targets: ".conversation-log",
      partial: "messages/message",
      locals: { message: fresh }
    )
  end

  # One LinkPreview per URL, not per message: the same article gets pasted into
  # twenty rooms, and fetching it twenty times points this app at whoever was
  # linked. A fresh row is fetched; an existing one is reused unless it has gone
  # stale.
  def attach_link_preview
    url = LinkPreview.first_url_in(content)
    return if url.blank?

    preview = LinkPreview.find_or_create_by!(url: url)
    update_column(:link_preview_id, preview.id)
    LinkPreviewFetchJob.perform_later(preview.id) if preview.stale?
  rescue ActiveRecord::RecordNotUnique
    # Two messages carrying the same new URL raced. The loser adopts the row.
    preview = LinkPreview.find_by(url: url)
    update_column(:link_preview_id, preview.id) if preview
  end

# One insert for the room, not one per person in it. A twenty-person channel
# paid twenty INSERTs on every message, inside the request that sent it.
def deliver_receipts
  now = Time.current
  ids = conversation.participants.where.not(id: sender_id).pluck(:id)
  return if ids.empty?

  MessageReceipt.insert_all(
    ids.map { |uid| { message_id: id, user_id: uid, delivered_at: now, created_at: now, updated_at: now } },
  )
end

  def clear_typing_indicators
    TypingIndicator.where(conversation:, user: sender).delete_all
  end

  def schedule_expiration
    expiry = expires_at || (Time.current + conversation.disappearing_duration.seconds)
    update_column(:expires_at, expiry) if expires_at.nil?
    MessageExpirationJob.set(wait_until: expiry).perform_later(id)
  end
end
