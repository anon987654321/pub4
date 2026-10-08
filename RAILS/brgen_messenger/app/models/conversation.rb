# frozen_string_literal: true

class Conversation < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Channels
  include GeoRooms
  include Unread

  belongs_to :city, optional: true
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, inclusion: { in: %w[direct group] }

  scope :for_user, ->(u) { joins(:conversation_participants).where(conversation_participants: { user: u }) }
  scope :channels, -> { where(conversation_type: "group").where.not(slug: nil).order(:slug) }

  # find_or_create_by! is a read then a write, and two joins of the same room
  # interleave between the halves. The unique index added in
  # 20260825120000 is what actually stops the second write; this rescue is how
  # the loser of that race gets the winner's row instead of a 500. Without both,
  # a duplicate row split `last_read_at` and the unread badge never cleared.
  def join!(user, role: "member")
    membership = begin
      conversation_participants.find_or_create_by!(user_id: user.id)
    rescue ActiveRecord::RecordNotUnique
      conversation_participants.find_by!(user_id: user.id)
    end
    # Only ever raise a role (member -> voice -> op); a bot re-seated or a human
    # re-opening the room never loses its mode.
    if ConversationParticipant::RANK.fetch(role, 0) > ConversationParticipant::RANK.fetch(membership.role, 0)
      membership.update!(role: role)
    end
    membership
  end

  # The messenger list, in one SQL order: the viewer's pins first, newest pin
  # above older ones, then everything else by its last message. Ordering in Ruby
  # after the fact would pin nothing on page two, because the page is chosen
  # before the sort. Reads the joined participant row that `for_user` already
  # filters to the viewer, so it is their pins and nobody else's.
  INBOX_ORDER = Arel.sql(
    "CASE WHEN conversation_participants.pinned_at IS NULL THEN 1 ELSE 0 END, " \
    "conversation_participants.pinned_at DESC, " \
    "COALESCE((SELECT MAX(m.created_at) FROM messages m " \
    "WHERE m.conversation_id = conversations.id), conversations.created_at) DESC"
  )

  # Two subqueries, not two calls to for_user. `for_user(a).for_user(b)` reads
  # as an intersection and is not one: both scopes join the SAME association, so
  # Rails collapses them into one join and ANDs the predicates on it —
  # `user_id = a AND user_id = b` on a single row, which no row satisfies. This
  # method therefore always answered nil, find_or_create_direct always created,
  # and every pair of people got a fresh thread each time they opened a DM from
  # a different button, splitting their history across duplicates.
  def self.direct_between(a, b)
    where(conversation_type: "direct")
      .where(id: ConversationParticipant.where(user_id: a.id).select(:conversation_id))
      .where(id: ConversationParticipant.where(user_id: b.id).select(:conversation_id))
      .order(:id).first
  end

  def self.find_or_create_direct(a, b)
    direct_between(a, b) || create!(conversation_type: "direct").tap do |c|
      c.participants << a << b
    end
  end

  # A group DM: a named conversation with more than two people in it, as opposed
  # to a #channel, which is a public room with a slug. Both are
  # conversation_type "group"; slug is what tells them apart, and every DM
  # surface already filters on `slug: nil`.
  MAX_GROUP_PARTICIPANTS = 50

  def self.create_group!(creator:, name:, users: [])
    transaction do
      group = create!(conversation_type: "group", name: name.to_s.strip.presence, city: Current.city_record)
      # The creator is an op. Nothing else in the app appoints one, so a group
      # created without an op could never be renamed or moderated by anyone.
      group.join!(creator, role: "op")
      users.uniq.excluding(creator).each { |user| group.join!(user) }
      group
    end
  end

  def group_dm? = conversation_type == "group" && slug.blank?

  # Ops rename the room and remove people; any member may add. A group chat
  # where only the founder can bring a friend in is one people work around by
  # starting a second group.
  def admin?(user)
    return false if user.blank?

    conversation_participants.exists?(user_id: user.id, role: "op")
  end

  # A group without an op can never be renamed or moderated again, so the last
  # one leaving hands the room to whoever has been in it longest rather than
  # being refused — refusing would trap someone in a chat they want to leave.
  def promote_longest_standing!
    return if conversation_participants.exists?(role: "op")

    conversation_participants.order(:created_at, :id).first&.update!(role: "op")
  end

  DISAPPEARING_OPTIONS = {
    "off" => nil,
    "1m" => 60,
    "5m" => 300,
    "1h" => 3600,
    "24h" => 86_400
  }.freeze

  def disappearing_messages? = disappearing_duration.present? && disappearing_duration.positive?

  def display_name_for(user)
    return name if conversation_type == "group" && name.present?

    other_participants(user).first&.display_name || "Unknown"
  end

  # reject when the association is already loaded, where.not when it is not.
  #
  # Every caller of display_name_for renders a list — the inbox, the rooms rail,
  # the forward-target picker — and every one of those controllers preloads
  # :participants. A `where` on an association ignores that and issues its own
  # SELECT, so the preload was bought and then bypassed once per row. Adding the
  # rail made it two lists per page and the query budget caught it; the defect was
  # already there in the inbox.
  #
  # Same family as message_receipts.find_by and outfit.items.count: `where`,
  # `find_by` and `count` all go to the database whatever is in memory, while
  # `reject`, `detect` and `size` read what is there.
  def other_participants(user)
    return participants.reject { |p| p.id == user.id } if participants.loaded?

    participants.where.not(id: user.id)
  end
end
