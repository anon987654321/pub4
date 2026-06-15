# frozen_string_literal: true

module Shared
  module AuthSessionHooks
    extend ActiveSupport::Concern
    include Shared::RememberMe
    include Shared::AuthRateLimiting
    include Shared::DeviceFingerprinting
    include Shared::SuspiciousLoginDetection

    private

    def resume_authenticated_user
      return if Current.user.present? && !Current.user.try(:guest?)

      remembered = resume_remembered_user
      return if remembered
    end

    def complete_login_for(user, remember: false)
      if auth_rate_limited?
        redirect_to new_session_path, alert: "Too many attempts. Try again in 15 minutes."
        return false
      end

      unless user
        record_failed_auth_attempt
        return false
      end

      clear_auth_attempts
      start_new_session_for(user)
      remember_user(user) if remember
      log_device_fingerprint(user)
      check_suspicious_login(user)
      true
    end

    def complete_logout_for(user = Current.user)
      forget_remembered_user(user)
      terminate_session
    end
  end
end