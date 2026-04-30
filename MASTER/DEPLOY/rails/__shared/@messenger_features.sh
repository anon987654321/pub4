#!/usr/bin/env zsh
# __shared/@messenger_features.sh — Messenger-style chat models for Rails 8
# Source from app installers. Do not execute directly.
set -euo pipefail

setup_messenger_models() {
  log "Setting up messenger models"

  generate_model Conversation \
    name:string conversation_type:string \
    last_message_at:datetime

  generate_model ConversationParticipant \
    conversation:references user:references \
    last_read_at:datetime muted:boolean:default[false]

  generate_model Message \
    conversation:references user:references \
    content:text message_type:string \
    read_at:datetime edited_at:datetime \
    deleted_at:datetime

  log_ok "Messenger models ready"
}

write_messenger_model_logic() {
  cat > app/models/conversation.rb << 'RUBY'
class Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy

  validates :conversation_type, inclusion: { in: %w[direct group] }

  scope :for_user, ->(user) {
    joins(:conversation_participants).where(conversation_participants: { user: user })
  }

  def self.direct_between(user1, user2)
    joins(:conversation_participants)
      .where(conversation_type: "direct")
      .where(conversation_participants: { user: user1 })
      .joins(:conversation_participants)
      .where(conversation_participants: { user: user2 })
      .first
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user: user)
    return 0 unless participant
    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
  end

  def mark_read_by!(user)
    conversation_participants.find_by(user: user)&.update!(last_read_at: Time.current)
  end
end
RUBY

  cat > app/models/message.rb << 'RUBY'
class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  has_many_attached :attachments

  validates :content, presence: true, unless: :has_attachments?
  validates :message_type, inclusion: { in: %w[text image file voice] }

  default_scope -> { where(deleted_at: nil).order(:created_at) }

  after_create_commit :update_conversation_timestamp
  after_create_commit :broadcast_to_conversation

  def soft_delete!
    update!(deleted_at: Time.current, content: "Message deleted")
  end

  def edited?
    edited_at.present?
  end

  private

  def has_attachments?
    attachments.any?
  end

  def update_conversation_timestamp
    conversation.update_column(:last_message_at, Time.current)
  end

  def broadcast_to_conversation
    broadcast_append_to [conversation, "messages"],
      partial: "messages/message",
      locals: { message: self }
  end
end
RUBY

  cat > app/controllers/conversations_controller.rb << 'RUBY'
class ConversationsController < ApplicationController
  before_action :require_authentication

  def index
    @conversations = Conversation.for_user(Current.user)
      .includes(:participants, :messages)
      .order(last_message_at: :desc)
  end

  def show
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    @conversation.mark_read_by!(Current.user)
    @messages = @conversation.messages.includes(:user).limit(50)
    @message = Message.new
  end

  def create
    recipient = User.find(params[:recipient_id])
    @conversation = Conversation.direct_between(Current.user, recipient) ||
      Conversation.create!(conversation_type: "direct")
    @conversation.participants << Current.user unless @conversation.participants.include?(Current.user)
    @conversation.participants << recipient unless @conversation.participants.include?(recipient)
    redirect_to @conversation
  end
end
RUBY

  cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  before_action :require_authentication
  before_action :set_conversation

  def create
    @message = @conversation.messages.build(message_params.merge(user: Current.user))
    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @conversation }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @message = @conversation.messages.find(params[:id])
    @message.soft_delete! if @message.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  end

  private

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:content, :message_type, attachments: [])
  end
end
RUBY
  log_ok "Messenger logic written"
}
