# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :require_user_session

  def index
    @conversations = Conversation.for_user(Current.user)
                                 .includes(:participants, :messages)
                                 .order("messages.created_at DESC")
  end

  def show
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    @conversation.mark_read_for!(Current.user)
    @messages = @conversation.messages.unexpired.recent.limit(50).reverse
    @message  = Message.new
  end

  def update
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    duration = Conversation::DISAPPEARING_OPTIONS[params[:disappearing]]
    if @conversation.update(disappearing_duration: duration)
      redirect_to @conversation, notice: "Disappearing messages updated"
    else
      redirect_to @conversation, alert: "Could not update settings"
    end
  end

  def create
    other = resolve_conversation_partner
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to @conversation
  rescue ActiveRecord::RecordNotFound
    redirect_to conversations_path, alert: "User not found"
  end

  private

  def resolve_conversation_partner
    if params[:username].present?
      User.find_by!(username: params[:username].to_s.strip.downcase)
    else
      User.find(params[:user_id])
    end
  end
end
