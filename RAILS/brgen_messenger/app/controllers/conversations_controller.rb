# frozen_string_literal: true

class ConversationsController < ApplicationController
  # #new is the people picker: apply_live_search and finish_live_search come from here.
  include Shared::LiveSearchable
  before_action :require_user_session
  # A guest can start a conversation, and everything a guest starts is a message
  # request (Conversation.known_to?). Requests are the spam channel, so a guest
  # opens a handful an hour; an account is limited by its sends instead.
  rate_limit to: 5, within: 1.hour, only: :create, name: "guest_requests",
             by: -> { "u#{Current.user.id}" }, if: -> { Current.user&.guest? },
             with: -> { redirect_to conversations_path, alert: t("flash.messages_rate_limited") }
  # The rail is part of the window, not part of the inbox, so it loads for the
  # room you are reading as well as for the list. Arriving straight at a
  # conversation URL used to give you that conversation and nothing else — no
  # way to reach another room without going back first. #show loads it itself,
  # after view-once messages are expired, so the rail's preview never shows a
  # line the thread has just removed.
  before_action :load_rail, only: :index

  def index
    # DMs only — public channels live under /channels, not the messenger list.
    # Ordered by Conversation::INBOX_ORDER: pins first, then newest message via
    # a correlated subquery rather than a raw "messages.created_at" order on an
    # unjoined table — the latter needs .references(:messages) and then
    # LEFT-JOIN-duplicates each conversation once per message.
    # ?arkiv=1 is the archive: the same list, the other half of the viewer's own
    # archive flag.
    # ?requests=1 is the third list: message requests waiting to be accepted.
    @archive = params[:arkiv].present?
    @requests = !@archive && params[:requests].present?
    @pagy, @conversations = pagy(
      listed_threads.includes(:participants).order(Conversation::INBOX_ORDER)
    )

    @last_messages = Conversation.last_messages_for(@conversations.map(&:id))
    # One grouped COUNT for the whole list. The view used to call
    # unread_count_for per row, which includes(:messages) does not help with —
    # it is a find_by plus its own COUNT, so the preload was paid and ignored.
    @unread_counts = Conversation.unread_counts_for(Current.user)
    # One pluck for the pin state of the page, for the same reason.
    @pinned_ids = ConversationParticipant.pinned
                                         .where(user_id: Current.user.id, conversation_id: @conversations.map(&:id))
                                         .pluck(:conversation_id).to_set
    @muted_ids = ConversationParticipant.muted
                                        .where(user_id: Current.user.id, conversation_id: @conversations.map(&:id))
                                        .pluck(:conversation_id).to_set
  end

  # Search the reader's own messages. Scoped through the conversations they
  # take part in, so a query cannot reach a thread they are not in, and it reads
  # `visible.unexpired` like every render does: a message that has disappeared
  # or been unsent must not come back through a search box, or ephemerality is
  # a rendering choice rather than a promise.
  # Starting a conversation used to mean typing someone's exact username into a
  # blank field on the inbox: you had to already know the handle of the person you
  # wanted, which is the one thing you do not know about someone you just met.
  # This is the same live-search machinery communities and events already use,
  # pointed at people, and every row carries the button that opens the thread.
  def new
    scope = User.messageable.unblocked_with(Current.user).where.not(id: Current.user.id)
    scope = apply_live_search(scope, columns: %w[username display_name], vertical: "people")
    # No query yet: show who is around rather than an empty box, the people the
    # reader follows or has talked to first.
    @people = PeoplePicker.rank(scope, Current.user).limit(24)
    finish_live_search(partial: "conversations/people_results")
  end

  def search
    @query = params[:q].to_s.strip
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id]) if params[:conversation_id].present?
    @messages = []
    return if @query.blank?

    scope = Message.visible.unexpired.where(conversation_id: searchable_conversation_ids)
    scope = scope.where(conversation_id: @conversation.id) if @conversation
    @pagy, @messages = pagy(
      Shared::LiveSearch.call(scope, query: @query, columns: %w[content])
                        .includes(:sender, :conversation).order(created_at: :desc)
    )
  end

  def show
    # participants for the group roster; strict loading makes that a preload
    # rather than a nice-to-have.
    @conversation = Conversation.for_user(Current.user).includes(:participants).find(params[:id])
    open_for_reader
    load_rail
    @blocked = @conversation.blocked_between?(Current.user)
    @blocked_by_me = @blocked && @conversation.other_participants(Current.user).any? { |other| Current.user.blocking?(other) }
    load_window
    @message = Message.new
    # A reply or an edit is chosen by a link, so the composer reads it off the
    # URL: no client state, and the choice survives a reload.
    @reply_to = @conversation.messages.visible.unexpired.find_by(id: params[:reply_to])
    @editing = @conversation.messages.find_by(id: params[:edit])
    @editing = nil unless @editing&.editable_by?(Current.user)
    @is_group_admin = @conversation.admin?(Current.user)
    @master_invited = @conversation.participants.any? { |participant| participant.bot? && participant.username == "master" }
  end

  def invite_master
    @conversation = Conversation.for_user(Current.user).includes(:participants).find(params[:id])
    master = ChannelBot.bot_for("master")
    @conversation.join!(master)
    unless @conversation.messages.where(sender: master).exists?
      @conversation.messages.create!(sender: master, message_type: "text", content: I18n.t("messages.master_joined"))
    end
    redirect_to @conversation, notice: t("flash.master_invited")
  end

  def update
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    # Channel/geo rooms inherit CHANNEL_TTL. Any member can hit this PATCH
    # (join! on GET /channels/:slug puts them in for_user), and a missing
    # disappearing param maps to nil — which turns the TTL off.
    if (refusal = disappearing_refusal)
      redirect_to @conversation, alert: t(refusal)
      return
    end
    duration = Conversation::DISAPPEARING_OPTIONS[params[:disappearing]]
    changed = @conversation.disappearing_duration != duration
    if @conversation.update(disappearing_duration: duration)
      announce_disappearing_change if changed
      redirect_to @conversation, notice: t("flash.disappearing_messages_updated")
    else
      redirect_to @conversation, alert: t("flash.settings_update_failed")
    end
  end

  def create
    other = resolve_conversation_partner
    if blocked_either_way?(other)
      redirect_to conversations_path, alert: t("flash.user_not_found")
      return
    end
    @conversation = Conversation.find_or_create_direct(Current.user, other, as_request: true)
    redirect_to @conversation
  rescue ActiveRecord::RecordNotFound
    redirect_to conversations_path, alert: t("flash.user_not_found")
  end

  private

  # Channel rooms keep CHANNEL_TTL; a group's timer is set by its ops.
  # A changed timer is said in the thread, as a line from whoever changed it,
  # so every participant sees who set it and to what. The sender is the who;
  # naming them in the text would undo an anonymous room's handles.
  def announce_disappearing_change
    setting = t("messages.disappearing_options.#{params[:disappearing]}")
    @conversation.messages.create!(sender: Current.user, message_type: "text",
                                   content: t("messages.disappearing_changed", setting:))
  end

  def disappearing_refusal
    return "flash.channel_ttl_locked" if @conversation.channel?
    return "flash.settings_update_failed" unless Conversation::DISAPPEARING_OPTIONS.key?(params[:disappearing])

    "flash.settings_update_failed" unless @conversation.disappearing_settable_by?(Current.user)
  end

  def open_for_reader
    # Before the read is recorded: what was opened on an earlier visit goes now,
    # and what is being opened for the first time stays for this one.
    @conversation.expire_read_messages!
    @participant = @conversation.conversation_participants.find_by(user: Current.user)
    # Opening a request is not reading it: the sender is told nothing until it
    # is accepted, which is the point of a request.
    @conversation.mark_read_for!(Current.user) unless @participant&.request?
  end

  def load_window
    # parent: :sender for the reply line, message_receipts for the read chip —
    # both are read once per message, so both are preloaded once per page.
    # The thread window and a history page are the same size, and one row more
    # than the window answers "is there more behind this?" — so show learns the
    # answer without paying a COUNT, and the log gets its first history cursor.
    thread = @conversation.messages
    @messages = thread.visible.unexpired
                      .includes(:sender, :message_receipts, :link_preview, :reactions, :conversation,
                                parent: :sender).with_attached_attachment
                      .recent.limit(MessagesController::HISTORY_PAGE + 1)
    @older_available = @messages.size > MessagesController::HISTORY_PAGE
    @messages = @messages.first(MessagesController::HISTORY_PAGE).reverse
  end

  # Which of the three lists this page is: its threads, its heading and the id
  # the inbox stream prepends into (only the inbox's own list takes new rows).
  LISTS = {
    inbox: %w[in_inbox messages.title inbox_conversations],
    archive: [ "in_archive", "messages.archive_title", "archived_conversations" ],
    requests: [ "in_requests", "messages.requests_title", "requested_conversations" ]
  }.freeze

  def listed_threads
    list = (:archive if @archive) || (:requests if @requests) || :inbox
    scope, @list_title_key, @list_id = LISTS.fetch(list)
    Conversation.for_user(Current.user).where(slug: nil).public_send(scope)
  end

  # The rooms rail: the reader's DMs, newest first, plus the public channels.
  # Deliberately not paginated — the rail is chrome, and an inbox long enough to
  # need a second page is long enough that the search box is the right tool. The
  # index still paginates its own list for the no-JS path.
  # The rail is a roster, not a feed: 30 rooms, no pager and no sentinel. Past
  # thirty the way to a room is search, which sits at the head of the rail for
  # that reason. #index's own @pagy/@conversations serve the <noscript> list only.
  def load_rail
    @rail_conversations = Conversation.for_user(Current.user)
                                      .where(slug: nil)
                                      .in_inbox
                                      .includes(:participants)
                                      .order(Conversation::INBOX_ORDER)
                                      .limit(30)
    count_side_lists
    @rail_last_messages = Conversation.last_messages_for(@rail_conversations.map(&:id))
    @rail_pinned, @rail_muted = ConversationParticipant.flag_sets_for(Current.user, @rail_conversations.map(&:id))
    @rail_unread = Conversation.unread_counts_for(Current.user)
  end

  # How many threads are put away and how many wait as requests, so the rail
  # links to each only when there is something behind the link.
  def count_side_lists
    threads = Conversation.for_user(Current.user).where(slug: nil)
    @archived_count = threads.in_archive.count
    @request_count = threads.in_requests.count
  end

  # DMs only, matching the list this search sits on. Public rooms are ambient
  # and already searchable by anyone who opens them; folding them in would make
  # "your messages" mean "everything you have ever walked past".
  def searchable_conversation_ids
    Conversation.for_user(Current.user).where(slug: nil).select(:id)
  end

  def resolve_conversation_partner
    if params[:username].present?
      User.messageable.find_by!(username: params[:username].to_s.strip.downcase)
    else
      User.messageable.find(params[:user_id])
    end
  end

  def blocked_either_way?(other)
    return false unless Current.user.respond_to?(:blocking?)

    Current.user.blocking?(other) || other.respond_to?(:blocking?) && other.blocking?(Current.user)
  end
end
