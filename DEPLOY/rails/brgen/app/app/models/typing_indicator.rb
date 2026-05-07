class TypingIndicator < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  scope :active, -> { where("expires_at > ?", Time.now) }

  def self.set!(conversation:, user:)
    rec = find_or_create_by(conversation:, user:)
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
