class TypingIndicator < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  scope :active, -> { where("expires_at > ?", Time.now) }

  def self.set!(conversation:, user:)
    find_or_create_by(conversation:, user:).update!(expires_at: 5.seconds.from_now)
  end
end
