# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :blog
  belongs_to :user, optional: true

  STATUSES = %w[inactive active canceled].freeze

  validates :status, inclusion: { in: STATUSES }

  def active?
    status == "active" && (expires_at.nil? || expires_at > Time.current)
  end
end