# frozen_string_literal: true

class Message < ApplicationRecord
  include Shared::MediaProcessable
  tracks_activity created: "MessageSent", source_vertical: "messages", actor: :sender

  include Shared::Notifiable
  include Shared::Reactable
  belongs_to :conversation
  belongs_to :sender, class_name: "User", foreign_key: :sender_id
  has_many :message_receipts, dependent: :destroy
  has_one_attached :attachment
  process_media_variants :attachment, variants: {
    inline: { resize_to_limit: [ 900, 900 ], format: :webp },
    thumb: { resize_to_limit: [ 320, 320 ], format: :webp }
  }

  validates :content, presence: true, length: { maximum: 10_000 }
  validates :message_type, inclusion: { in: %w[text image file audio] }

  broadcasts_to :conversation, inserts_by: :append, target: "messages"

  after_create :deliver_receipts
  after_create :clear_typing_indicators
  after_create :schedule_expiration, if: :should_expire?

  scope :recent, -> { order(created_at: :desc) }
  scope :unexpired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired? = expires_at&.past?

  def should_expire? = expires_at.present? || conversation.disappearing_messages?

  def mark_as_read!(user)
    receipt = message_receipts.find_or_initialize_by(user: user)
    receipt.update!(read_at: Time.current) unless receipt.read_at
  end

  def read_by?(user)
    message_receipts.where(user: user).where.not(read_at: nil).exists?
  end

  private

  def deliver_receipts
    conversation.participants.where.not(id: sender_id).each do |u|
      message_receipts.create!(user: u, delivered_at: Time.now)
    end
  end

  def clear_typing_indicators
    TypingIndicator.where(conversation:, user: sender).delete_all
  end

  def schedule_expiration
    expiry = expires_at || (Time.current + conversation.disappearing_duration.seconds)
    update_column(:expires_at, expiry) if expires_at.nil?
    MessageExpirationJob.set(wait_until: expiry).perform_later(id)
  end
end
