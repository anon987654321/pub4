# frozen_string_literal: true

module Shared
  module PasswordsActions
    extend ActiveSupport::Concern

    included do
      allow_unauthenticated_access
      before_action :set_user_by_token, only: %i[edit update]
      # name: is required once a controller has more than one rate_limit — the
      # cache key is ["rate-limit", controller_path, name, by], so two unnamed
      # limits share a counter. See RAILS/test/rate_limit_naming_test.rb.
      rate_limit to: 10, within: 3.minutes, only: :create, name: "request_reset",
        with: -> { redirect_to new_password_path, alert: t("shared.flash.rate_limited") }
      # update is the other half of the same flow and had no limit: it takes a
      # token from the URL and sets a password. The token is a signed
      # MessageVerifier value, so this is not a guessing hole — it is the half of
      # a rate-limited flow that was not rate limited, which is the shape that
      # survives review. Same budget as create, because they are one journey.
      rate_limit to: 10, within: 3.minutes, only: :update, name: "consume_reset",
        with: -> { redirect_to new_password_path, alert: t("shared.flash.rate_limited") }
    end

    def new
    end

    def create
      if user = User.find_by(email_address: params[:email_address])
        Shared::PasswordResetJob.perform_later(user.id)
      end

      redirect_to new_session_path,
        notice: t("shared.flash.password_reset_sent")
    end

    def edit
    end

    def update
      if @user.update(params.permit(:password, :password_confirmation))
        @user.sessions.destroy_all
        redirect_to new_session_path, notice: t("shared.flash.password_reset_done")
      else
        redirect_to edit_password_path(params[:token]), alert: t("shared.flash.passwords_did_not_match")
      end
    end

    private

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("shared.flash.password_reset_link_invalid")
    end
  end
end
