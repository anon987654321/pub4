# frozen_string_literal: true

module Shared
  # Enforce TOTP at sign-in for members who enabled it.
  #
  # TwoFactorSetupsController has always let a member turn TOTP on, and
  # TwoFactorAuth#require_two_factor! has always guarded the one action that
  # asked for it (brgen_marketplace listings) — but nothing challenged the
  # second factor when the session itself was created. A member who "enabled
  # 2FA" was protected by their password alone, which the setup page never
  # told them.
  #
  # The flag is written by Authentication#start_new_session_for for any user
  # carrying an otp_secret, so every sign-in path — password, magic link,
  # OAuth — goes through the same gate. start_new_session_for calls
  # reset_session first, so a fresh sign-in clears a stale pending flag by
  # construction. The gate admits only what the challenge needs: the sign-out
  # route and the setup/verify surface itself. Everyone else is redirected
  # until they present a current code.
  module TwoFactorGate
    extend ActiveSupport::Concern

    # controller_path values the challenge itself needs. Sign-out must stay
    # reachable (a member who cannot produce a code can still leave); account
    # settings is deliberately behind the gate, because disabling 2FA goes
    # through TwoFactorSetupsController#update, which demands a working code.
    CHALLENGE_CONTROLLER_PATHS = %w[sessions two_factor_setups].freeze

    included do
      # After Shared::Authentication's resume_session: Current.user must be
      # loaded before this reads it.
      before_action :enforce_two_factor_challenge
    end

    private

    def enforce_two_factor_challenge
      return unless session[:two_factor_pending]

      user = Current.user
      if user.blank? || user.try(:otp_secret).blank?
        # 2FA vanished under the flag — purged account, or disabled on another
        # device between sign-in and this request. Clear and continue; the
        # session itself is real, only the challenge is gone.
        session.delete(:two_factor_pending)
        return
      end

      return if CHALLENGE_CONTROLLER_PATHS.include?(controller_path)

      redirect_to Rails.application.routes.url_helpers.two_factor_setup_path,
                  alert: t("shared.flash.two_factor_required")
    end
  end
end
