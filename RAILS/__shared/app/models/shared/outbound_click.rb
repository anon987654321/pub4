# frozen_string_literal: true

module Shared
  # One recorded click on a link that leaves the site.
  #
  # This is the denominator. Affiliate revenue is clicks × conversion × basket ×
  # commission, and until this table existed the first term was unknown, so the
  # other three could not be judged: "nobody clicks" and "attribution is broken"
  # produce the same zero in a network dashboard.
  #
  # Stores a host, never a full URL. The question is which merchants get traffic,
  # not what each visitor shops for — and the narrower record is also the one that
  # does not become a liability.
  class OutboundClick < ApplicationRecord
    self.table_name = "outbound_clicks"

    # created_at only; there is nothing to update about a click.
    self.record_timestamps = false

    validates :app, :url_host, presence: true
    validates :url_host, length: { maximum: 255 }

    scope :since, ->(time) { where(created_at: time..) }
    scope :for_merchant, ->(merchant) { where(merchant:) }

    # A host, or nil for anything that is not an absolute http(s) URL — a relative
    # path, a javascript: URI, or junk. Returning nil means "do not record",
    # which is the honest answer for a click we cannot attribute to a merchant.
    def self.host_for(url)
      uri = URI.parse(url.to_s)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri.host.downcase.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end

    def self.record(app:, url:, surface: nil, merchant: nil, subject: nil, epi: nil, user: nil)
      host = host_for(url)
      return nil if host.blank?

      create!(
        app: app.to_s,
        surface: surface.presence&.to_s,
        merchant: merchant.presence&.to_s,
        url_host: host,
        subject_type: subject&.class&.name,
        subject_id: subject&.id,
        epi: epi.presence,
        user_id: user&.id,
        guest: user.respond_to?(:guest?) ? !!user.guest? : false,
        created_at: Time.current,
      )
    end

    # Clicks per merchant over a window, highest first — the report the operator
    # actually wants before deciding whether partner marketing is worth more work.
    def self.by_merchant(since: 30.days.ago)
      since(since).group(:merchant).order(count_all: :desc).count
    end
  end
end
