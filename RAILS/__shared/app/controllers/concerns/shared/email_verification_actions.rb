# frozen_string_literal: true

module Shared
  # Route actions used by every host app. The token is consumed with one atomic
  # conditional update, so a replay or a raced second click cannot confirm twice.
  module EmailVerificationActions
    extend ActiveSupport::Concern

    def show
      token = params[:token].to_s
      user = if token.present?
               User.where(deleted_at: nil, deletion_scheduled_at: nil)
                   .find_by(email_verification_token: token)
             end

      if user&.verify_email_token!(token)
        redirect_to root_path, notice: t("shared.email_verification.done")
      else
        redirect_to root_path, alert: t("shared.email_verification.invalid")
      end
    end

    def create
      user = Current.user
      if user.present? && !user.try(:guest?) && !user.email_verified?
        user.generate_email_verification!
        Shared::VerificationMailer.verify(user, request.host).deliver_later
      end

      redirect_back fallback_location: root_path, notice: t("shared.email_verification.resent")
    end
  end
end
