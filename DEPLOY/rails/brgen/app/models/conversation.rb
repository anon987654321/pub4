# frozen_string_literal: true

class Conversation < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, inclusion: { in: %w[direct group] }

  scope :for_user, ->(u) { joins(:conversation_participants).where(conversation_participants: { user: u }) }

  def self.direct_between(a, b)
    for_user(a).for_user(b).where(conversation_type: "direct").first
  end

  def self.find_or_create_direct(a, b)
    direct_between(a, b) || create!(conversation_type: "direct").tap do |c|
      c.participants << a << b
    end
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user:)
    return 0 unless participant
    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
  end

  def mark_read_for!(user)
    conversation_participants.find_by(user:)&.update!(last_read_at: Time.now)
    messages.unexpired.find_each do |message|
      receipt = message.message_receipts.find_or_initialize_by(user: user)
      receipt.update!(read_at: Time.current) unless receipt.read_at
    end
  end

  DISAPPEARING_OPTIONS = {
    "off" => nil,
    "1m" => 60,
    "5m" => 300,
    "1h" => 3600,
    "24h" => 86_400
  }.freeze

  def disappearing_messages? = disappearing_duration.present? && disappearing_duration.positive?

  def display_name_for(user)
    return name if conversation_type == "group" && name.present?

    other_participants(user).first&.display_name || "Unknown"
  end

  def other_participants(user)
    participants.where.not(id: user.id)
  end
end
