# frozen_string_literal: true

class SecurityAdvisory < ApplicationRecord
  enum :severity, { low: 0, medium: 1, high: 2, critical: 3 }, default: :medium

  belongs_to :port, optional: true

  validates :title, presence: true
  validates :identifier, uniqueness: true, allow_blank: true

  scope :recent, -> { order(published_at: :desc, updated_at: :desc) }
  scope :active, -> { where(resolved_at: nil) }

  after_create_commit { broadcast_prepend_later_to "bsdports:security_advisories" }
  after_update_commit { broadcast_replace_later_to "bsdports:security_advisories" }
end
