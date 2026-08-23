# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :require_user_session

  def index
    load_inbox
    @message = Current.user.sent_messages.build
    # One UPDATE, not one per message. This issued a write per unread row on a
    # GET, so opening a large inbox turned a read into an unbounded write burst.
    # update_all skips callbacks and updated_at by design — read_at is the fact
    # being recorded, and nothing keys a cache on a message's updated_at.
    Current.user.received_messages.unread.update_all(read_at: Time.current)
  end

  def create
    @message = Current.user.sent_messages.build(message_params)
    @message.recipient = Current.user.messageable_users.find_by(id: @message.recipient_id)
    if @message.recipient && @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to messages_path, notice: t("flash.message_sent") }
      end
    else
      @message.errors.add(:recipient_id, :invalid) if @message.recipient.nil?
      load_inbox
      render :index, status: :unprocessable_entity
    end
  end

  private

  def message_params = params.require(:message).permit(:recipient_id, :body)

  def load_inbox
    @pagy, @messages = pagy(
      Message.where(sender: Current.user).or(Message.where(recipient: Current.user))
             .includes(sender: :profile, recipient: :profile).recent
    )
    @unread_count = Current.user.received_messages.unread.count
    @recipients = Current.user.messageable_users
  end
end
