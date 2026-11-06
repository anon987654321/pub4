# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :require_verified_email, only: :create
  before_action :require_user_session

  # One row per person, latest message first, until a row is opened: then the
  # messages with that person alone (?with=id), the composer addressed to them.
  # The read marking is unchanged: opening the inbox reads it, so a row's
  # unread dot is what arrived since the last visit.
  def index
    @partner = conversation_partner(params[:with]) if params[:with].present?
    return redirect_to(messages_path) if params[:with].present? && @partner.nil?

    @partner ? load_thread : load_conversations
    # A connection's Message link names the person; the select starts on them.
    @message = Current.user.sent_messages.build(recipient_id: @partner&.id || params[:recipient_id].presence)
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
      # The recipient's inbox row comes back with its unread dot if they have
      # written since the viewer last opened the inbox.
      @unread_from = Current.user.received_messages.unread.where(sender: @message.recipient).distinct.pluck(:sender_id)
      respond_to do |format|
        format.turbo_stream { render from_widget? ? :create_widget : :create }
        format.html { redirect_to messages_path(with: params[:with].presence), notice: t("flash.message_sent") }
      end
    else
      @message.errors.add(:recipient_id, :invalid) if @message.recipient.nil?
      load_conversations
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

  # One lookup per request: master_invited?, resolve_recipient and load_inbox
  # each ran this find_by, up to three times for one send. The ivar is set
  # even when the row is absent, so nil is remembered too.
  def master
    return @master if defined?(@master)

    @master = User.find_by(email_address: "master@amber.local", bot: true)
  end

  def master_invited?
    return @master_invited if defined?(@master_invited)

    @master_invited = master.present? && Current.user.received_messages.where(sender: master).exists?
  end

  def resolve_recipient(id)
    return master if master && master.id == id.to_i && master_invited?

    Current.user.messageable_users.find_by(id:) || connected_recipient(id)
  end

  # A random pairing (EncountersController) accepts a connection between two
  # strangers, guests included. The public directory stays messageable_users -
  # the inbox list never grows by accident - but an accepted connection is
  # itself the permission to write, whoever the two people are.
  def connected_recipient(id)
    id = id.to_i
    linked = Connection.accepted.where(requester_id: Current.user.id, addressee_id: id)
                       .or(Connection.accepted.where(addressee_id: Current.user.id, requester_id: id))
    User.find_by(id: id) if linked.exists?
  end

  # Someone the viewer has a message with; nobody else opens as a conversation.
  # A fresh random pairing has no messages yet, so the accepted connection
  # carries the thread until the first line is written.
  def conversation_partner(id)
    User.includes(:profile).where(id: Message.partner_ids(Current.user)).find_by(id:) ||
      User.includes(:profile).find_by(id: connected_partner_id(id))
  end

  def connected_partner_id(id)
    id = id.to_i
    linked = Connection.accepted.where(requester_id: Current.user.id, addressee_id: id)
                       .or(Connection.accepted.where(addressee_id: Current.user.id, requester_id: id))
    id if linked.exists?
  end

  def load_conversations
    latest = Message.latest_per_partner(Current.user)
    @pagy, @conversations = pagy(latest.includes(sender: :profile, recipient: :profile).recent)
    @unread_from = Current.user.received_messages.unread.distinct.pluck(:sender_id).to_set
    load_counts
  end

  def load_thread
    thread = Message.between(Current.user, @partner)
    @pagy, @messages = pagy(thread.includes(sender: :profile, recipient: :profile).recent)
    load_counts
  end

  def load_counts
    @unread_count = Current.user.received_messages.unread.count
    @recipients = Current.user.messageable_users.to_a
    @recipients << master if master && master_invited?
  end

  def load_inbox
    @pagy, @messages = pagy(
      Message.where(sender: Current.user).or(Message.where(recipient: Current.user))
             .includes(sender: :profile, recipient: :profile).recent
    )
    @unread_count = Current.user.received_messages.unread.count
    @recipients = Current.user.messageable_users.to_a
    @recipients << master if master && master_invited?
  end
end
