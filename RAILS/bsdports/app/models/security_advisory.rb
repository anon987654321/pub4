# frozen_string_literal: true

class SecurityAdvisory < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  enum :severity, { low: 0, medium: 1, high: 2, critical: 3 }, default: :medium

  belongs_to :port, optional: true

  validates :title, presence: true
  validates :identifier, uniqueness: true, allow_blank: true

  scope :recent, -> { order(published_at: :desc, updated_at: :desc) }
  scope :active, -> { where(resolved_at: nil) }

  # Two broadcasts to "bsdports:security_advisories" were here, both with no
  # partial (implicit to_partial_path resolved to
  # security_advisories/_security_advisory, and bsdports has no
  # app/views/security_advisories at all), no target, and no subscriber — nothing in
  # the app calls turbo_stream_from for that stream. Advisories render inside
  # ports/show.html.erb and arrive from the nightly NVD cross-reference, not from a
  # user action someone is watching for, so there is nothing a live prepend would
  # improve. Removed rather than wired.

  def nvd_url
    source_url.presence || (identifier.present? ? "https://nvd.nist.gov/vuln/detail/#{identifier}" : nil)
  end

  def cve?
    identifier.to_s.start_with?("CVE-")
  end
end
