# frozen_string_literal: true

class SecurityAdvisory < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  enum :severity, { low: 0, medium: 1, high: 2, critical: 3 }, default: :medium

  belongs_to :port, optional: true

  validates :title, presence: true
  validates :identifier, uniqueness: true, allow_blank: true

  scope :recent, -> { order(published_at: :desc, updated_at: :desc) }
  scope :active, -> { where(resolved_at: nil) }

  after_create_commit { broadcast_prepend_later_to "bsdports:security_advisories" }
  after_update_commit { broadcast_replace_later_to "bsdports:security_advisories" }

  def nvd_url
    source_url.presence || (identifier.present? ? "https://nvd.nist.gov/vuln/detail/#{identifier}" : nil)
  end

  def cve?
    identifier.to_s.start_with?("CVE-")
  end
end
