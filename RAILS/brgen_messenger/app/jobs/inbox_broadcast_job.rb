# frozen_string_literal: true

# Keeps each reader's inbox live: their row for one thread in the inbox list
# and the rooms rail, and the unread count on the Messenger entry. Before this
# the list, the rail and the badge changed only on a reload, so a message sent
# to someone reading their inbox did not appear there.
#
# Rendered once per reader into that reader's own signed stream ([user, :inbox],
# subscribed in the layout), which is why a per-person render is correct here
# where it is wrong for a conversation's shared stream: the name, the unread
# count and the pin are the reader's own. A job, because a group message means
# one render per member and none of that belongs in the sender's request.
class InboxBroadcastJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  # Where each row lives: the list a moved thread is prepended to, and the dom
  # id prefix a redrawn one is replaced at.
  ROWS = {
    "conversations/conversation_row" => [ "inbox_conversations", :inbox ],
    "conversations/rail_row" => [ "rail_conversations", :rail ]
  }.freeze

  # The unread count is drawn in two places, each with its own id: the
  # Messenger entry in the swiper, and the tab bar's Messages icon, whose copy
  # also carries the count the tab title shows.
  BADGES = { "messenger_unread_badge" => false, "messenger_unread_badge_tab" => true }.freeze

  # moved: a new message, so the thread goes to the top of the list (a pinned
  # one stays among the pins, redrawn where it is). Otherwise the thread was
  # read, muted, pinned, edited or unsent and the row is redrawn in place.
  # user_ids nil means everyone in the thread.
  def perform(conversation_id, user_ids = nil, moved: false)
    @conversation = Conversation.strict_loading(false).includes(:participants, :city).find_by(id: conversation_id)
    # Channels are ambient: they have no inbox row and do not light the badge.
    return if @conversation.nil? || @conversation.slug.present?

    @moved = moved
    ActsAsTenant.with_tenant(@conversation.city) do
      I18n.with_locale(city_locale) do
        @last_messages = Conversation.last_messages_for([ @conversation.id ])
        readers(user_ids).each { |membership| refresh(membership) }
      end
    end
  end

  private

  def readers(user_ids)
    memberships = @conversation.conversation_participants
    scope = memberships.strict_loading(false).includes(:user)
    scope = scope.where(user_id: user_ids) if user_ids
    scope.reject { |membership| membership.user.bot? || membership.user.guest? }
  end

  # Not `locale`: ActiveJob::Core owns that name for the enqueuer's locale.
  def city_locale
    wanted = @conversation.city&.locale.presence&.to_sym
    I18n.available_locales.include?(wanted) ? wanted : I18n.default_locale
  end

  def refresh(membership)
    reader = membership.user
    draw_rows(reader, pinned: membership.pinned?, muted: membership.muted?) if membership.listed?

    count = Conversation.unread_total_for(reader)
    BADGES.each do |badge_id, title|
      Turbo::StreamsChannel.broadcast_replace_to(
        reader, :inbox, target: badge_id, partial: "conversations/unread_badge",
                        locals: { count:, badge_id:, title: }
      )
    end
  end

  def draw_rows(reader, pinned:, muted:)
    unread = @conversation.unread_count_for(reader)
    last = @last_messages[@conversation.id]
    move = @moved && !pinned

    place(reader, "conversations/conversation_row", move:,
          locals: { conversation: @conversation, viewer: reader, unread:, pinned:, muted:, last:, archived: false })
    place(reader, "conversations/rail_row", move:,
          locals: { room: @conversation, viewer: reader, unread_counts: { @conversation.id => unread },
                    last_messages: @last_messages, pinned_ids: flag_set(pinned), muted_ids: flag_set(muted) })
  end

  # The rail row reads the reader's pins and mutes as sets of ids.
  def flag_set(flag) = flag ? Set[@conversation.id] : Set.new

  # A prepend with the row's id moves it: Turbo removes the list's existing
  # child with the same id before inserting, so a thread already on screen is
  # not drawn twice, and one that was not is added at the top.
  def place(reader, partial, move:, locals:)
    list, prefix = ROWS.fetch(partial)
    if move
      Turbo::StreamsChannel.broadcast_prepend_to(reader, :inbox, target: list, partial:, locals:)
    else
      row = ActionView::RecordIdentifier.dom_id(@conversation, prefix)
      Turbo::StreamsChannel.broadcast_replace_to(reader, :inbox, target: row, partial:, locals:)
    end
  end
end
