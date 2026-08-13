# frozen_string_literal: true

# A remote actor following a local user.
#
# The row exists while still pending, because Follow and Accept are separate
# round trips: if the Accept never lands, the remote side believes it succeeded
# and we have to be able to tell that from never having been asked.
class FediFollow < ApplicationRecord
  STATES = %w[pending accepted].freeze

  belongs_to :fedi_actor
  belongs_to :user

  validates :state, inclusion: { in: STATES }
  validates :fedi_actor_id, uniqueness: { scope: :user_id }

  scope :accepted, -> { where(state: "accepted") }

  def accept! = update!(state: "accepted")
end
