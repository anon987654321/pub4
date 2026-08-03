# frozen_string_literal: true

class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :show
  rate_limit to: 5, within: 5.minutes, only: :create,
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }

  # Confirm via the emailed link.
  def show
    user = User.find_by(email_verification_token: params[:token].to_s) if params[:token].present?
    if user
      user.verify_email!
      redirect_to main_app.root_path, notice: t("verify.done", default: "Email confirmed — thanks!")
    else
      redirect_to main_app.root_path, alert: t("verify.invalid", default: "That confirmation link is invalid or already used.")
    end
  end

  # Resend, for the signed-in but unverified user.
  def create
    if Current.user && !Current.user.guest? && !Current.user.email_verified?
      Current.user.generate_email_verification!
      VerificationMailer.verify(Current.user).deliver_later
    end
    redirect_back fallback_location: main_app.root_path,
                  notice: t("verify.resent", default: "Verification email sent — check your inbox.")
  end
end
