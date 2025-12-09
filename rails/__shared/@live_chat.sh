#!/usr/bin/env zsh
set -euo pipefail

# Live Chat Feature: Real-time messaging with WebSockets, typing indicators, read receipts
# Telegram/Snapchat-style instant messaging for any Rails app
# Uses ActionCable + Turbo Streams for real-time updates

setup_live_chat_models() {
  log "Setting up Live Chat models: Conversation, Message, MessageReceipt, TypingIndicator"

  bin/rails generate model Conversation conversation_type:string name:string disappearing_duration:integer
  bin/rails generate model ConversationParticipant conversation:references user:references last_read_at:datetime notifications_enabled:boolean
  bin/rails generate model Message conversation:references sender:references{user} content:text message_type:string encrypted:boolean expires_at:datetime
  bin/rails generate model MessageReceipt message:references user:references delivered_at:datetime read_at:datetime
  bin/rails generate model TypingIndicator conversation:references user:references expires_at:datetime
  bin/rails generate model MessageAttachment message:references attachment_type:string file_url:string thumbnail_url:string metadata:json

  log "Live Chat models generated"
}

generate_live_chat_models() {
  log "Configuring Live Chat models with real-time features"

  cat <<'EOF' > app/models/conversation.rb
class Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, presence: true, inclusion: { in: %w[direct group] }
  enum conversation_type: { direct: "direct", group: "group" }

  scope :for_user, ->(user) { joins(:conversation_participants).where(conversation_participants: { user: user }) }

  def latest_message
    messages.order(created_at: :desc).first
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user: user)
    return 0 unless participant

    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
  end

  def mark_read_for(user)
    participant = conversation_participants.find_by(user: user)
    participant&.update(last_read_at: Time.current)
  end

  def other_participant(user)
    participants.where.not(id: user.id).first if direct?
  end
end
EOF

  cat <<'EOF' > app/models/message.rb
class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  has_many :message_receipts, dependent: :destroy
  has_many :message_attachments, dependent: :destroy

  validates :content, presence: true, unless: -> { message_attachments.any? }
  validates :message_type, inclusion: { in: %w[text image video audio file] }

  after_create_commit :broadcast_message
  after_create_commit :create_receipts
  after_create_commit :clear_typing_indicator

  scope :recent, -> { order(created_at: :desc).limit(50) }

  def broadcast_message
    broadcast_append_to(
      [conversation, :messages],
      partial: "messages/message",
      locals: { message: self },
      target: "messages"
    )
  end

  def create_receipts
    conversation.participants.each do |participant|
      next if participant == sender

      message_receipts.create(user: participant, delivered_at: Time.current)
    end
  end

  def clear_typing_indicator
    conversation.typing_indicators.where(user: sender).delete_all
  end

  def read_by?(user)
    message_receipts.exists?(user: user, read_at: !nil)
  end

  def mark_read_by(user)
    receipt = message_receipts.find_by(user: user)
    receipt&.update(read_at: Time.current)
  end
end
EOF

  cat <<'EOF' > app/models/typing_indicator.rb
class TypingIndicator < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  after_create_commit :broadcast_typing
  after_destroy_commit :broadcast_stopped_typing

  def self.cleanup_expired
    where("expires_at < ?", Time.current).delete_all
  end

  private

  def broadcast_typing
    broadcast_update_to(
      [conversation, :typing],
      partial: "conversations/typing",
      locals: { conversation: conversation },
      target: "typing-indicator-#{conversation.id}"
    )
  end

  def broadcast_stopped_typing
    broadcast_update_to(
      [conversation, :typing],
      partial: "conversations/typing",
      locals: { conversation: conversation },
      target: "typing-indicator-#{conversation.id}"
    )
  end
end
EOF

  log "Live Chat models configured with real-time broadcasting"
}

generate_live_chat_controllers() {
  log "Generating Live Chat controllers"

  mkdir -p app/controllers/chat

  cat <<'EOF' > app/controllers/chat/conversations_controller.rb
module Chat
  class ConversationsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_conversation, only: [:show, :destroy]

    def index
      @conversations = Conversation.for_user(current_user).order(updated_at: :desc)
    end

    def show
      @messages = @conversation.messages.recent.reverse
      @conversation.mark_read_for(current_user)
    end

    def create
      @conversation = Conversation.create!(conversation_params)
      @conversation.conversation_participants.create!(user: current_user)

      participant_ids = params[:participant_ids] || []
      participant_ids.each do |user_id|
        @conversation.conversation_participants.create!(user_id: user_id)
      end

      redirect_to chat_conversation_path(@conversation)
    end

    def destroy
      @conversation.destroy
      redirect_to chat_conversations_path, notice: "Conversation deleted"
    end

    private

    def set_conversation
      @conversation = Conversation.for_user(current_user).find(params[:id])
    end

    def conversation_params
      params.require(:conversation).permit(:conversation_type, :name, :disappearing_duration)
    end
  end
end
EOF

  cat <<'EOF' > app/controllers/chat/messages_controller.rb
module Chat
  class MessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_conversation

    def create
      @message = @conversation.messages.build(message_params)
      @message.sender = current_user

      if @message.save
        head :ok
      else
        render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_conversation
      @conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    end

    def message_params
      params.require(:message).permit(:content, :message_type)
    end
  end
end
EOF

  cat <<'EOF' > app/controllers/chat/typing_indicators_controller.rb
module Chat
  class TypingIndicatorsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_conversation

    def create
      @conversation.typing_indicators.where(user: current_user).delete_all
      @conversation.typing_indicators.create!(
        user: current_user,
        expires_at: 5.seconds.from_now
      )

      head :ok
    end

    private

    def set_conversation
      @conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    end
  end
end
EOF

  log "Live Chat controllers generated"
}

generate_live_chat_stimulus_controller() {
  log "Generating Live Chat Stimulus controller"

  mkdir -p app/javascript/controllers

  cat <<'EOF' > app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "messages"]
  static values = { conversationId: String }

  connect() {
    this.scrollToBottom()
    this.typingTimeout = null
  }

  submit(event) {
    event.preventDefault()
    const content = this.inputTarget.value.trim()

    if (!content) return

    fetch(`/chat/conversations/${this.conversationIdValue}/messages`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ message: { content, message_type: "text" } })
    }).then(() => {
      this.inputTarget.value = ""
      this.scrollToBottom()
    })
  }

  typing() {
    clearTimeout(this.typingTimeout)

    fetch(`/chat/conversations/${this.conversationIdValue}/typing_indicators`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content
      }
    })

    this.typingTimeout = setTimeout(() => {
      // Typing indicator expires automatically after 5 seconds
    }, 3000)
  }

  scrollToBottom() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }
}
EOF

  log "Live Chat Stimulus controller generated"
}

generate_live_chat_routes() {
  log "Adding Live Chat routes"

  cat <<'EOF' >> config/routes.rb
  namespace :chat do
    resources :conversations, only: [:index, :show, :create, :destroy] do
      resources :messages, only: [:create]
      resources :typing_indicators, only: [:create]
    end
  end
EOF

  log "Live Chat routes added"
}

setup_live_chat() {
  setup_live_chat_models
  generate_live_chat_models
  generate_live_chat_controllers
  generate_live_chat_stimulus_controller
  generate_live_chat_routes
  
  log "Live Chat feature complete: Real-time messaging with typing indicators and read receipts"
}
