# frozen_string_literal: true
# AN211: Suspicious login detection via ipapi.co (demo/fallback mode)

module Shared
  module SuspiciousLoginDetection
    extend ActiveSupport::Concern

    private

    def check_suspicious_login(user)
      country = geolocate_country(request.remote_ip)
      return unless country

      previous = user.last_login_country
      user.update_column(:last_login_country, country) if user.respond_to?(:last_login_country)

      return if previous.blank? || previous == country

      Shared::SuspiciousLoginMailer.new_country_alert(user, country, previous).deliver_later
    rescue StandardError => e
      Rails.logger.info("[suspicious_login] demo/fallback: #{e.message}")
    end

    def geolocate_country(ip)
      return "NO" if ip.start_with?("127.", "192.168.", "10.")

      cache_key = "geo:country:#{ip}"
      Rails.cache.fetch(cache_key, expires_in: 24.hours) do
        if ENV["IPAPI_ENABLED"] == "true"
          require "net/http"
          uri = URI("https://ipapi.co/#{ip}/country/")
          response = Net::HTTP.get_response(uri)
          response.code == "200" ? response.body.strip : "UNKNOWN"
        else
          "NO" # demo fallback
        end
      end
    end
  end
end