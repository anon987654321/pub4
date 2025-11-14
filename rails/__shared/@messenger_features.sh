#!/usr/bin/env zsh
set -euo pipefail

# Telegram/Snapchat messenger features: Direct Messages, Typing Indicators, Read Receipts, Disappearing Messages
# Shared across social apps (brgen sms.brgen.no subdomain)

setup_messenger_models() {
  log "Setting up Messenger models: Conversation, Message, MessageReceipt, TypingIndicator"

  # Conversation model (1-on-1 or group)
  bin/rails generate model Conversation conversation_type:string name:string disappearing_duration:integer

  # Join table for conversation participants
  bin/rails generate model ConversationParticipant conversation:references user:references last_read_at:datetime notifications_enabled:boolean

  # Message model with encryption support
  bin/rails generate model Message conversation:references sender:references{user} content:text message_type:string encrypted:boolean expires_at:datetime

  # Message delivery and read receipts
  bin/rails generate model MessageReceipt message:references user:references delivered_at:datetime read_at:datetime

  # Typing indicator
  bin/rails generate model TypingIndicator conversation:references user:references expires_at:datetime

  # Media attachments for messages
  bin/rails generate model MessageAttachment message:references attachment_type:string file_url:string thumbnail_url:string metadata:json

  log "Messenger models generated"
}

generate_conversation_model() {
  log "Configuring Conversation model"

  cat <<'EOF' > app/models/conversation.rb
class Conversation < ApplicationRecord

  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user

  has_many :messages, dependent: :destroy

  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, presence: true, inclusion: { in: %w[direct group] }

  enum conversation_type: {

    direct: "direct",
    group: "group"
  }

  scope :for_user, ->(user) { joins(:conversation_participants).where(conversation_participants: { user: user }) }

  def latest_message

    messages.order(created_at: :desc).first
  end
  def unread_count_for(user)

    participant = conversation_participants.find_by(user: user)

    return 0 unless participant
    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count

  end

  def mark_as_read!(user)
    participant = conversation_participants.find_by(user: user)

    participant&.update(last_read_at: Time.current)
  end

  def other_participants(current_user)

    participants.where.not(id: current_user.id)

  end
  def display_name_for(current_user)

    return name if group?

    other_participant = other_participants(current_user).first
    other_participant&.email || "Unknown"

  end
  def disappearing_messages?

    disappearing_duration.present? && disappearing_duration > 0

  end
end

EOF

  log "Conversation model configured"

}

generate_conversation_participant_model() {
  log "Configuring ConversationParticipant model"

  cat <<'EOF' > app/models/conversation_participant.rb
class ConversationParticipant < ApplicationRecord

  belongs_to :conversation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :conversation_id }

  def unread_count

    conversation.messages.where("created_at > ?", last_read_at || Time.at(0)).count
  end
end

EOF

  log "ConversationParticipant model configured"

}

generate_message_model() {
  log "Configuring Message model"

  cat <<'EOF' > app/models/message.rb
class Message < ApplicationRecord

  belongs_to :conversation
  belongs_to :sender, class_name: "User"

  has_many :message_receipts, dependent: :destroy

  has_many :message_attachments, dependent: :destroy

  validates :content, presence: true, unless: :has_attachments?

  validates :message_type, presence: true, inclusion: { in: %w[text image video audio file] }

  after_create :create_receipts_for_participants
  after_create :schedule_expiration, if: :should_expire?

  after_create_commit :broadcast_to_conversation
  enum message_type: {

    text: "text",

    image: "image",
    video: "video",

    audio: "audio",

    file: "file"

  }

  scope :unexpired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  scope :for_user, ->(user) {

    joins(conversation: :conversation_participants)
      .where(conversation_participants: { user: user })

  }

  def has_attachments?

    message_attachments.any?

  end
  def delivered_to?(user)

    message_receipts.exists?(user: user, delivered_at: Time.current)

  end
  def read_by?(user)

    message_receipts.exists?(user: user, read_at: Time.current)

  end
  def mark_as_delivered!(user)

    receipt = message_receipts.find_or_initialize_by(user: user)

    receipt.update(delivered_at: Time.current) unless receipt.delivered_at
  end

  def mark_as_read!(user)

    receipt = message_receipts.find_or_initialize_by(user: user)

    receipt.update(read_at: Time.current) unless receipt.read_at
  end

  def should_expire?

    expires_at.present? || conversation.disappearing_messages?

  end
  def schedule_expiration

    expiration_time = expires_at || (Time.current + conversation.disappearing_duration.seconds)

    MessageExpirationJob.set(wait_until: expiration_time).perform_later(id)
  end

  private

  def create_receipts_for_participants

    conversation.participants.where.not(id: sender_id).find_each do |participant|
      message_receipts.create(user: participant)
    end

  end

  def broadcast_to_conversation

    broadcast_append_to(

      conversation,
      target: "messages",

      partial: "messages/message",

      locals: { message: self }

    )

  end

end

EOF

  log "Message model configured"

}

generate_message_receipt_model() {
  log "Configuring MessageReceipt model"

  cat <<'EOF' > app/models/message_receipt.rb
class MessageReceipt < ApplicationRecord

  belongs_to :message
  belongs_to :user

  validates :user_id, uniqueness: { scope: :message_id }

  scope :delivered, -> { where.not(delivered_at: nil) }

  scope :read, -> { where.not(read_at: nil) }
  def delivered?
    delivered_at.present?

  end
  def read?

    read_at.present?

  end
end

EOF

  log "MessageReceipt model configured"

}

generate_typing_indicator_model() {
  log "Configuring TypingIndicator model"

  cat <<'EOF' > app/models/typing_indicator.rb
class TypingIndicator < ApplicationRecord

  belongs_to :conversation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :conversation_id }

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.start_typing(conversation, user)
    indicator = find_or_initialize_by(conversation: conversation, user: user)
    indicator.expires_at = 10.seconds.from_now
    indicator.save

    broadcast_typing_status(conversation, user, true)

  end

  def self.stop_typing(conversation, user)
    indicator = find_by(conversation: conversation, user: user)

    indicator&.destroy
    broadcast_typing_status(conversation, user, false)

  end

  def self.broadcast_typing_status(conversation, user, is_typing)
    broadcast_replace_to(

      conversation,
      target: "typing-indicator-#{user.id}",

      partial: "conversations/typing_indicator",

      locals: { user: user, is_typing: is_typing }

    )

  end

end

EOF

  log "TypingIndicator model configured"

}

generate_message_attachment_model() {
  log "Configuring MessageAttachment model"

  cat <<'EOF' > app/models/message_attachment.rb
class MessageAttachment < ApplicationRecord

  belongs_to :message
  validates :attachment_type, :file_url, presence: true

  enum attachment_type: {

    image: "image",
    video: "video",
    audio: "audio",

    document: "document"

  }

  def display_name

    metadata&.dig("original_filename") || File.basename(file_url)

  end
  def file_size

    metadata&.dig("size")

  end
end

EOF

  log "MessageAttachment model configured"

}

extend_user_for_messaging() {
  log "Extending User model with messaging features"

  cat <<'EOF' >> app/models/user.rb
  # Messenger features

  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants
  has_many :sent_messages, class_name: "Message", foreign_key: :sender_id, dependent: :destroy

  def start_conversation_with(other_user)

    # Find existing direct conversation

    existing = Conversation.direct
                          .joins(:conversation_participants)

                          .where(conversation_participants: { user: self })

                          .joins("INNER JOIN conversation_participants cp2 ON cp2.conversation_id = conversations.id")

                          .where("cp2.user_id = ?", other_user.id)

                          .first

    return existing if existing

    # Create new conversation

    conversation = Conversation.create!(conversation_type: :direct)
    conversation.conversation_participants.create!(user: self, notifications_enabled: true)
    conversation.conversation_participants.create!(user: other_user, notifications_enabled: true)

    conversation

  end

  def create_group_conversation(name, participant_users)

    conversation = Conversation.create!(conversation_type: :group, name: name)

    ([self] + participant_users).uniq.each do |user|
      conversation.conversation_participants.create!(user: user, notifications_enabled: true)

    end

    conversation

  end

  def total_unread_messages

    conversation_participants.sum { |cp| cp.unread_count }

  end
EOF

  log "User extended with messaging features"

}

generate_conversations_controller() {
  log "Generating ConversationsController"

  cat <<'EOF' > app/controllers/conversations_controller.rb
class ConversationsController < ApplicationController

  before_action :authenticate_user!
  def index

    @conversations = current_user.conversations

                                 .includes(:participants, :messages)
                                 .order("messages.created_at DESC")

  end

  def show

    @conversation = current_user.conversations.find(params[:id])

    @conversation.mark_as_read!(current_user)
    @messages = @conversation.messages.unexpired.order(created_at: :asc)

    @message = @conversation.messages.build

  end

  def create

    other_user = User.find(params[:user_id])

    @conversation = current_user.start_conversation_with(other_user)
    redirect_to conversation_path(@conversation)

  end

  def destroy
    @conversation = current_user.conversations.find(params[:id])

    participant = @conversation.conversation_participants.find_by(user: current_user)
    participant.destroy

    redirect_to conversations_path, notice: "Left conversation"

  end

  def start_typing
    @conversation = current_user.conversations.find(params[:id])

    TypingIndicator.start_typing(@conversation, current_user)
    head :ok

  end

  def stop_typing
    @conversation = current_user.conversations.find(params[:id])

    TypingIndicator.stop_typing(@conversation, current_user)
    head :ok

  end

end
EOF

  log "ConversationsController generated"

}

generate_messages_controller() {
  log "Generating MessagesController"

  cat <<'EOF' > app/controllers/messages_controller.rb
class MessagesController < ApplicationController

  before_action :authenticate_user!
  before_action :set_conversation

  def create

    @message = @conversation.messages.build(message_params)

    @message.sender = current_user
    @message.message_type = determine_message_type

    if @message.save

      # Mark as delivered for all online participants

      broadcast_delivery_receipts
      respond_to do |format|

        format.turbo_stream

        format.html { redirect_to conversation_path(@conversation) }
      end

    else

      render "conversations/show", status: :unprocessable_entity

    end

  end

  def mark_as_read

    @message = @conversation.messages.find(params[:id])

    @message.mark_as_read!(current_user)
    head :ok

  end

  private
  def set_conversation

    @conversation = current_user.conversations.find(params[:conversation_id])
  end
  def message_params

    params.require(:message).permit(:content, :expires_at)

  end
  def determine_message_type

    # In production, check for attachments

    :text
  end

  def broadcast_delivery_receipts

    @conversation.participants.where.not(id: current_user.id).find_each do |participant|

      # In production, check if user is online via ActionCable
      @message.mark_as_delivered!(participant)

    end

  end

end

EOF

  log "MessagesController generated"

}

generate_conversation_list_partial() {
  log "Generating conversation list partial"

  mkdir -p app/views/conversations
  cat <<'EOF' > app/views/conversations/_conversation_item.html.erb

<%= tag.div class: "conversation-item", id: dom_id(conversation) do %>
  <%= link_to conversation_path(conversation), class: "conversation-link" do %>
    <%= tag.div class: "conversation-avatar" do %>

      <% if conversation.group? %>

        <%= tag.span conversation.name.first %>

      <% else %>

        <%= tag.span conversation.other_participants(current_user).first&.email&.first %>

      <% end %>

    <% end %>

    <%= tag.div class: "conversation-details" do %>

      <%= tag.div class: "conversation-header" do %>

        <%= tag.span conversation.display_name_for(current_user), class: "conversation-name" %>
        <%= tag.span time_ago_in_words(conversation.latest_message&.created_at || conversation.created_at), class: "conversation-time" %>

      <% end %>

      <%= tag.div class: "conversation-preview" do %>

        <% latest = conversation.latest_message %>

        <% if latest %>
          <%= tag.span "#{latest.sender.email.split('@').first}: #{latest.content.truncate(50)}", class: "message-preview" %>

        <% else %>

          <%= tag.span "No messages yet", class: "message-preview empty" %>

        <% end %>

        <% unread = conversation.unread_count_for(current_user) %>

        <% if unread > 0 %>

          <%= tag.span unread, class: "unread-badge" %>
        <% end %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

EOF

  log "Conversation list partial generated"

}

generate_message_partial() {
  log "Generating message partial"

  mkdir -p app/views/messages
  cat <<'EOF' > app/views/messages/_message.html.erb

<%= tag.div class: "message #{message.sender == current_user ? 'sent' : 'received'}", id: dom_id(message) do %>
  <%= tag.div class: "message-content" do %>
    <%= tag.div class: "message-sender" do %>

      <%= message.sender.email.split('@').first %>

    <% end %>

    <%= tag.div class: "message-body" do %>

      <%= simple_format message.content %>

    <% end %>
    <%= tag.div class: "message-meta" do %>

      <%= tag.span time_ago_in_words(message.created_at), class: "message-time" %>

      <% if message.sender == current_user %>
        <%= tag.span class: "message-status" do %>

          <% if message.message_receipts.all?(&:read?) %>
            <span class="status-read">✓✓</span>

          <% elsif message.message_receipts.any?(&:delivered?) %>

            <span class="status-delivered">✓✓</span>

          <% else %>

            <span class="status-sent">✓</span>

          <% end %>

        <% end %>

      <% end %>

      <% if message.expires_at %>

        <%= tag.span "🔥 #{distance_of_time_in_words_to_now(message.expires_at)}", class: "message-expiry" %>

      <% end %>
    <% end %>

  <% end %>

<% end %>

EOF

  log "Message partial generated"

}

generate_message_form_partial() {
  log "Generating message form partial"

  cat <<'EOF' > app/views/conversations/_message_form.html.erb
<%= tag.div id: "message-form-container", data: { controller: "message-composer" } do %>

  <%= form_with model: [@conversation, @message],
                data: {

                  action: "turbo:submit-start->message-composer#stopTyping input->message-composer#startTyping",

                  message_composer_target: "form"

                },

                class: "message-form" do |form| %>

    <%= tag.div id: "typing-indicators" do %>

      <% @conversation.typing_indicators.active.where.not(user: current_user).each do |indicator| %>

        <%= tag.span "#{indicator.user.email.split('@').first} is typing...", class: "typing-indicator" %>
      <% end %>

    <% end %>

    <%= tag.div class: "message-input-container" do %>

      <%= form.text_area :content,

          placeholder: "Type a message...",
          rows: 1,

          data: {

            message_composer_target: "input",

            action: "input->message-composer#autoResize"

          },

          class: "message-input" %>

      <%= tag.div class: "message-actions" do %>

        <%= tag.button "📎", type: "button", class: "btn-attach", title: "Attach file" %>

        <% if @conversation.disappearing_messages? %>
          <%= tag.span "🔥 #{@conversation.disappearing_duration}s", class: "disappearing-indicator" %>

        <% end %>
        <%= form.submit "Send", class: "btn-send" %>

      <% end %>

    <% end %>
  <% end %>

<% end %>

EOF

  log "Message form partial generated"

}

generate_message_composer_stimulus() {
  log "Generating Stimulus controller for message composer"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/message_composer_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["input", "form"]

  static values = { conversationId: Number }
  connect() {

    this.typingTimeout = null

  }
  startTyping() {

    clearTimeout(this.typingTimeout)

    // Send typing indicator
    fetch(`/conversations/${this.conversationIdValue}/start_typing`, {

      method: "POST",
      headers: {

        "X-CSRF-Token": this.csrfToken,

        "Content-Type": "application/json"

      }

    })

    // Auto-stop after 10 seconds

    this.typingTimeout = setTimeout(() => {

      this.stopTyping()
    }, 10000)

  }

  stopTyping() {

    clearTimeout(this.typingTimeout)

    fetch(`/conversations/${this.conversationIdValue}/stop_typing`, {
      method: "POST",

      headers: {
        "X-CSRF-Token": this.csrfToken,

        "Content-Type": "application/json"

      }

    })

  }

  autoResize() {

    const input = this.inputTarget

    input.style.height = "auto"
    input.style.height = input.scrollHeight + "px"

  }

  get csrfToken() {

    return document.querySelector("[name='csrf-token']").content

  }
}

EOF

  log "Message composer Stimulus controller generated"

}

add_messenger_routes() {
  log "Adding Messenger feature routes"

  local routes_file="config/routes.rb"
  local temp_file="${routes_file}.tmp"

  # Pure zsh route handling
  cat <<'EOF' >> "$temp_file"

  # Telegram/Snapchat messenger features
  resources :conversations, only: [:index, :show, :create, :destroy] do

    member do
      post :start_typing

      post :stop_typing

    end

    resources :messages, only: [:create] do

      member do

        post :mark_as_read

      end

    end

  end

end

EOF

  mv "$temp_file" "$routes_file"

  log "Messenger routes added"

}
setup_messenger_features() {
  setup_messenger_models

  generate_conversation_model
  generate_conversation_participant_model

  generate_message_model

  generate_message_receipt_model

  generate_typing_indicator_model

  generate_message_attachment_model

  extend_user_for_messaging

  generate_conversations_controller

  generate_messages_controller

  generate_conversation_list_partial

  generate_message_partial

  generate_message_form_partial

  generate_message_composer_stimulus

  add_messenger_routes

  log "Telegram/Snapchat messenger features fully configured!"

}

