# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :require_user_session

  def index
    # DMs only — public channels live under /channels, not the messenger list.
    # Order by newest message via a correlated subquery, not a raw
    # "messages.created_at" order on an unjoined table — the latter needs
    # .references(:messages) and then LEFT-JOIN-duplicates each conversation once
    # per message. COALESCE to created_at keeps empty conversations in order.
    @pagy, @conversations = pagy(
      Conversation.for_user(Current.user)
                  .where(slug: nil)
                  .includes(:participants, :messages)
                  .order(Arel.sql(
                    "COALESCE((SELECT MAX(m.created_at) FROM messages m " \
                    "WHERE m.conversation_id = conversations.id), " \
                    "conversations.created_at) DESC"
                  ))
    )
    # One grouped COUNT for the whole list. The view used to call
    # unread_count_for per row, which includes(:messages) does not help with —
    # it is a find_by plus its own COUNT, so the preload was paid and ignored.
    @unread_counts = Conversation.unread_counts_for(Current.user)
  end

  def show
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    @conversation.mark_read_for!(Current.user)
    @messages = @conversation.messages.visible.unexpired.recent.limit(50).reverse
    @message  = Message.new
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
