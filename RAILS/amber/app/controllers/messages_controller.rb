# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :require_real_user

  def index
    @messages = Message.where(sender: Current.user).or(Message.where(recipient: Current.user)).includes(:sender, :recipient).recent
    @unread_count = Current.user.received_messages.unread.count
    @message = Current.user.sent_messages.build
    Current.user.received_messages.unread.find_each(&:read!)
  end

  def create
    @message = Current.user.sent_messages.build(message_params)
    if @message.save
      redirect_to messages_path, notice: "Message sent"
    else
      @messages = Message.where(sender: Current.user).or(Message.where(recipient: Current.user)).includes(:sender, :recipient).recent
      @unread_count = Current.user.received_messages.unread.count
      render :index, status: :unprocessable_entity
    end
  end

  private

  def message_params = params.require(:message).permit(:recipient_id, :body)
end
