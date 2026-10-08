# frozen_string_literal: true

# One row per activity we have already handled.
#
# An inbox POST arriving twice is routine rather than exceptional: delivery
# retries on any non-2xx and several implementations retry optimistically. The
# unique index on uri is what makes processing idempotent.
class FediActivity < ApplicationRecord
  belongs_to :fedi_actor, optional: true

  validates :uri, presence: true, uniqueness: true
end
