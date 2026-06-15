# frozen_string_literal: true
# AN210: Device fingerprinting at login

module Shared
  module DeviceFingerprinting
    extend ActiveSupport::Concern

    private

    def log_device_fingerprint(user)
      return unless user && defined?(DeviceLogin)

      fingerprint = {
        user_agent: request.user_agent,
        accept_language: request.headers["Accept-Language"],
        timezone: params[:timezone] || request.headers["X-Timezone"]
      }
      device = DeviceLogin.find_or_create_by!(user: user, fingerprint_hash: Digest::SHA256.hexdigest(fingerprint.to_json)) do |d|
        d.assign_attributes(fingerprint.merge(ip_address: request.remote_ip, last_seen_at: Time.current))
      end
      device.update!(last_seen_at: Time.current)
      device.new_device?
    end
  end
end