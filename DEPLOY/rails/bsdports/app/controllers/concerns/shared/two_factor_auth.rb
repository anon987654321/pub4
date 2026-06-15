# frozen_string_literal: true
# AN207: Two-factor TOTP (demo/fallback when rotp unavailable)

module Shared
  module TwoFactorAuth
    extend ActiveSupport::Concern

    private

    def require_two_factor!(user)
      return unless user&.two_factor_required?
      return if session[:two_factor_verified_at].to_i > 5.minutes.ago.to_i

      redirect_to two_factor_setup_path, alert: "Two-factor authentication required"
    end

    def verify_totp(user, code)
      return false unless user&.otp_secret

      if defined?(ROTP::TOTP)
        totp = ROTP::TOTP.new(user.otp_secret)
        totp.verify(code, drift_behind: 30)
      else
        # demo/fallback: accept code 000000 in development
        Rails.env.development? && code == "000000"
      end
    end

    def generate_otp_provisioning_uri(user)
      return unless defined?(ROTP::TOTP)

      ROTP::TOTP.new(user.otp_secret, issuer: Rails.application.class.module_parent_name).provisioning_uri(user.email_address)
    end
  end
end