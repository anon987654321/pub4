# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :require_user_session

  def index
    load_inbox
    @message = Current.user.sent_messages.build
    @master_invited = master_invited?
    # One UPDATE, not one per message. This issued a write per unread row on a
    # GET, so opening a large inbox turned a read into an unbounded write burst.
    # update_all skips callbacks and updated_at by design — read_at is the fact
    # being recorded, and nothing keys a cache on a message's updated_at.
    Current.user.received_messages.unread.update_all(read_at: Time.current)
  end

  def widget
    load_inbox
    @message = Current.user.sent_messages.build
  end

  def create
    @message = Current.user.sent_messages.build(message_params)
    @message.recipient = resolve_recipient(@message.recipient_id)
    if @message.recipient && @message.save
      respond_to do |format|
        format.turbo_stream { render from_widget? ? :create_widget : :create }
        format.html { redirect_to messages_path, notice: t("flash.message_sent") }
      end
    else
      @message.errors.add(:recipient_id, :invalid) if @message.recipient.nil?
      load_inbox
      render :index, status: :unprocessable_entity
    end
  end

  def invite_master
    master = User.master_bot
    unless Current.user.received_messages.where(sender: master).exists?
      master.sent_messages.create!(recipient: Current.user, body: t("messages.master_joined"))
    end
    redirect_to messages_path, notice: t("flash.master_invited")
  end

  private

  def from_widget? = params[:origin] == "widget"

  def message_params = params.require(:message).permit(:recipient_id, :body)

  def master_invited?
    master = User.find_by(email_address: "master@amber.local", bot: true)
    master.present? && Current.user.received_messages.where(sender: master).exists?
  end

  def resolve_recipient(id)
    master = User.find_by(email_address: "master@amber.local", bot: true)
    return master if master && master.id == id.to_i && master_invited?

    Current.user.messageable_users.find_by(id:)
  end

  def load_inbox
    @pagy, @messages = pagy(
      Message.where(sender: Current.user).or(Message.where(recipient: Current.user))
             .includes(sender: :profile, recipient: :profile).recent
    )
    @unread_count = Current.user.received_messages.unread.count
    @recipients = Current.user.messageable_users.to_a
    master = User.find_by(email_address: "master@amber.local", bot: true)
    @recipients << master if master && master_invited?
  end
end
