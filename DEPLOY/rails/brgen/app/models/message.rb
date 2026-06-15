# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: "User", foreign_key: :sender_id
  has_many :message_receipts, dependent: :destroy
  has_one_attached :attachment

  validates :content, presence: true, length: { maximum: 10_000 }
  validates :message_type, inclusion: { in: %w[text image file audio] }

  broadcasts_to :conversation, inserts_by: :append, target: "messages"

  after_create :deliver_receipts
  after_create :clear_typing_indicators
  after_create_commit :broadcast_badge_counts

  scope :recent, -> { order(created_at: :desc) }

  def expired? = expires_at&.past?

  private

  def deliver_receipts
    conversation.participants.where.not(id: sender_id).each do |u|
      message_receipts.create!(user: u, delivered_at: Time.now)
    end
  end

  def clear_typing_indicators
    TypingIndicator.where(conversation:, user: sender).delete_all
  end

  def broadcast_badge_counts
    conversation.participants.where.not(id: sender_id).each do |recipient|
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_badge_#{recipient.id}",
        target: "app-badge-count",
        partial: "shared/app_badge",
        locals: { count: Conversation.for_user(recipient).sum { |c| c.unread_count_for(recipient) } }
      )
    end
  end
end
