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
  end
end
