# frozen_string_literal: true

require "cgi"

module Shared
  # Server-side gate for purposes that may load optional client technology.
  # The browser writes the same versioned, purpose-scoped signal.
  module ConsentHelper
    CONSENT_COOKIE = "pub4_consent"
    CONSENT_VERSION = "v1"
    PURPOSES = %w[analytics advertising].freeze

    def advertising_consent?
      consented_for?("advertising")
    end

    def analytics_consent?
      consented_for?("analytics")
    end

    def consented_for?(purpose)
      consent_purposes.include?(purpose.to_s)
    end

    def consent_decided?
      raw = consent_signal
      return false if raw.blank?

      version, recorded_at, = CGI.unescape(raw).split("|", 3)
      version == CONSENT_VERSION && recorded_at.present?
    end

    def consent_purposes
      raw = consent_signal
      return [] if raw.blank?

      version, recorded_at, purposes = CGI.unescape(raw).split("|", 3)
      return [] unless version == CONSENT_VERSION && recorded_at.present?

      Array(purposes).first.to_s.split(",") & PURPOSES
    end

    private

    def consent_signal
      return "" unless respond_to?(:cookies)

      cookies[CONSENT_COOKIE].to_s
    end
  end
end
