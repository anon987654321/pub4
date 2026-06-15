# frozen_string_literal: true

class Message < ApplicationRecord
  include Shared::ActivityTrackable
  tracks_activity created: "MessageSent", source_vertical: "messages", actor: :sender

  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  belongs_to :conversation
  belongs_to :sender, class_name: "User", foreign_key: :sender_id
  has_many :message_receipts, dependent: :destroy
  has_one_attached :attachment

  validates :content, presence: true, length: { maximum: 10_000 }
  validates :message_type, inclusion: { in: %w[text image file audio] }

  broadcasts_to :conversation, inserts_by: :append, target: "messages"

  after_create :deliver_receipts
  after_create :clear_typing_indicators

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
end
