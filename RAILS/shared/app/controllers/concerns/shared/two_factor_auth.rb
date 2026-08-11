# frozen_string_literal: true

module Shared
  module TwoFactorAuth
    extend ActiveSupport::Concern

    TOTP_ISSUER = "pub4"

    private

    def verify_totp(user, code)
      return false if user.blank? || code.blank? || user.otp_secret.blank?

      ROTP::TOTP.new(user.otp_secret).verify(code.to_s.strip, drift_behind: 1, drift_ahead: 1)
    end

    def generate_otp_provisioning_uri(user)
      return if user.blank? || user.otp_secret.blank?

      ROTP::TOTP.new(user.otp_secret, issuer: TOTP_ISSUER).provisioning_uri(user.email_address)
    end

    def require_two_factor!(user)
      return unless user&.two_factor_required?
      return if session[:two_factor_verified_at].to_i > 1.hour.ago.to_i

      redirect_to two_factor_setup_path, alert: t("shared.flash.two_factor_required")
    end
  end
end
