# frozen_string_literal: true

# A follow, in either direction.
#
# `inbound` is a remote actor following a local user; `outbound` is a local user
# following a remote actor. One table rather than two of the same shape — the
# pair (actor, user) is the same fact either way, and only the arrow differs.
#
# The row exists while still pending, because Follow and Accept are separate
# round trips: if the Accept never lands, the other side believes it succeeded
# and we have to be able to tell that from never having been asked.
class FediFollow < ApplicationRecord
  STATES = %w[pending accepted].freeze
  DIRECTIONS = %w[inbound outbound].freeze

  belongs_to :fedi_actor
  belongs_to :user

  validates :state, inclusion: { in: STATES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :fedi_actor_id, uniqueness: { scope: %i[user_id direction] }

  scope :accepted, -> { where(state: "accepted") }
  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }

  def accept! = update!(state: "accepted")
end
