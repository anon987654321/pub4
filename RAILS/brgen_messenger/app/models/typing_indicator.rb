# frozen_string_literal: true

class TypingIndicator < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  # Backs the unique index in 20260825120000. This is the highest-frequency
  # write in the app — every keystroke burst in every open thread — so it is
  # the one most likely to actually interleave.
  validates :user_id, uniqueness: { scope: :conversation_id }

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.set!(conversation:, user:)
    rec = begin
      find_or_create_by(conversation:, user:)
    rescue ActiveRecord::RecordNotUnique
      find_by!(conversation:, user:)
    end
    rec.update!(expires_at: 5.seconds.from_now)
    Turbo::StreamsChannel.broadcast_replace_to(
      conversation,
      target:  "typing-indicator",
      partial: "typing_indicators/indicator",
      locals:  { conversation:, except_user: user }
    )
    rec
  end
end
