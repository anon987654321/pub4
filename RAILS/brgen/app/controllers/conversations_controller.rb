# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :require_user_session

  def index
    # DMs only — public channels live under /channels, not the messenger list.
    # Ordered by Conversation::INBOX_ORDER: pins first, then newest message via
    # a correlated subquery rather than a raw "messages.created_at" order on an
    # unjoined table — the latter needs .references(:messages) and then
    # LEFT-JOIN-duplicates each conversation once per message.
    @pagy, @conversations = pagy(
      Conversation.for_user(Current.user)
                  .where(slug: nil)
                  .includes(:participants, :messages)
                  .order(Conversation::INBOX_ORDER)
    )
    # One grouped COUNT for the whole list. The view used to call
    # unread_count_for per row, which includes(:messages) does not help with —
    # it is a find_by plus its own COUNT, so the preload was paid and ignored.
    @unread_counts = Conversation.unread_counts_for(Current.user)
    # One pluck for the pin state of the page, for the same reason.
    @pinned_ids = ConversationParticipant.pinned
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
  scope = User.messageable.where.not(id: Current.user.id)
  scope = apply_live_search(scope, columns: %w[username display_name], vertical: "people")
  # No query yet: show who is around rather than an empty box. Newest first is
  # the closest thing to "recently active" without another column.
  @people = scope.order(created_at: :desc).limit(24)
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
    @conversation.mark_read_for!(Current.user)
    # parent: :sender for the reply line, message_receipts for the read chip —
    # both are read once per message, so both are preloaded once per page.
    @messages = @conversation.messages.visible.unexpired
                             .includes(:sender, :message_receipts, :link_preview, parent: :sender)
                             .recent.limit(50).reverse
    @message = Message.new
    # Where a forward can go: the reader's other threads. Built once for the
    # page rather than per message.
    @forward_targets = Conversation.for_user(Current.user).where(slug: nil).where.not(id: @conversation.id)
                                   .includes(:participants)
                                   .map { |other| [ other.display_name_for(Current.user), other.id ] }
    # A reply or an edit is chosen by a link, so the composer reads it off the
    # URL: no client state, and the choice survives a reload.
    @reply_to = @conversation.messages.visible.unexpired.find_by(id: params[:reply_to])
    @editing = @conversation.messages.find_by(id: params[:edit])
    @editing = nil unless @editing&.editable_by?(Current.user)
    @is_group_admin = @conversation.admin?(Current.user)
  end

  def update
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    # Channel/geo rooms inherit CHANNEL_TTL. Any member can hit this PATCH
    # (join! on GET /channels/:slug puts them in for_user), and a missing
    # disappearing param maps to nil — which turns the TTL off.
    if @conversation.channel?
      redirect_to @conversation, alert: t("flash.channel_ttl_locked")
      return
    end
    unless Conversation::DISAPPEARING_OPTIONS.key?(params[:disappearing])
      redirect_to @conversation, alert: t("flash.settings_update_failed")
      return
    end
    duration = Conversation::DISAPPEARING_OPTIONS[params[:disappearing]]
    if @conversation.update(disappearing_duration: duration)
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
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to @conversation
  rescue ActiveRecord::RecordNotFound
    redirect_to conversations_path, alert: t("flash.user_not_found")
  end

  private

  # DMs only, matching the list this search sits on. Public rooms are ambient
  # and already searchable by anyone who opens them; folding them in would make
  # "your messages" mean "everything you have ever walked past".
  def searchable_conversation_ids
    Conversation.for_user(Current.user).where(slug: nil).select(:id)
  end

  def resolve_conversation_partner
    if params[:username].present?
      User.find_by!(username: params[:username].to_s.strip.downcase)
    else
      User.find(params[:user_id])
    end
  end

  def blocked_either_way?(other)
    return false unless Current.user.respond_to?(:blocking?)

    Current.user.blocking?(other) || other.respond_to?(:blocking?) && other.blocking?(Current.user)
  end
end
