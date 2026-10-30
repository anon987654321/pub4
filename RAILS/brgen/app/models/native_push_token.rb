# frozen_string_literal: true

# An APNs device token from the iOS shell. One device has one token; it moves
# to whoever signed in on that device last.
class NativePushToken < ApplicationRecord
  # sandbox for a development build, production for TestFlight and the store:
  # APNs keeps them apart, and a token sent to the wrong one is rejected.
  ENVIRONMENTS = %w[production sandbox].freeze

  belongs_to :user

  validates :token, presence: true, uniqueness: true, format: { with: /\A\h{64,200}\z/ }
  validates :environment, inclusion: { in: ENVIRONMENTS }
end
