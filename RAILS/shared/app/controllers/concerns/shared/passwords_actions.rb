# frozen_string_literal: true

module Shared
  module PasswordsActions
    extend ActiveSupport::Concern

    included do
      allow_unauthenticated_access
      before_action :set_user_by_token, only: %i[edit update]
      rate_limit to: 10, within: 3.minutes, only: :create,
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
