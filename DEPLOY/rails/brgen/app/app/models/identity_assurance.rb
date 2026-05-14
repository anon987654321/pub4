# frozen_string_literal: true

class IdentityAssurance < ApplicationRecord
  LEVELS = %w[guest account phone bankid merchant moderator].freeze

  belongs_to :user

  validates :level, inclusion: { in: LEVELS }
  validates :source, presence: true
end
