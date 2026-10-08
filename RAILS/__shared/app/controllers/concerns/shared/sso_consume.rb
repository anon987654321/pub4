# frozen_string_literal: true

module Shared
  # Consumes a MASTER-issued SSO token and starts a local session.
  # Host app must implement find_or_create_sso_user(email:, display_name:) and start_sso_session!(user).
  module SsoConsume
    extend ActiveSupport::Concern

    included do
      allow_unauthenticated_access only: :from_master if respond_to?(:allow_unauthenticated_access)
    end

    def from_master
      app = sso_app_name
      payload = Shared::SsoToken.verify(params[:token].to_s, expected_app: app)
      unless payload
        redirect_to(sso_failure_path, alert: t("shared.flash.sso_link_invalid"))
        return
      end

      user = find_or_create_sso_user(
        email: payload["email"],
        display_name: payload["display_name"],
      )
      unless user
        redirect_to(sso_failure_path, alert: t("shared.flash.sso_session_failed", email: payload["email"]))
        return
      end

      start_sso_session!(user)
      redirect_to(sso_success_path, notice: t("shared.flash.signed_in_via_master"))
    end

    private

    def sso_app_name
      Rails.application.class.module_parent_name.to_s.downcase
    end

    def sso_failure_path
      respond_to?(:new_session_path) ? new_session_path : "/"
    end

    def sso_success_path
      respond_to?(:root_path) ? root_path : "/"
    end
  end
end
