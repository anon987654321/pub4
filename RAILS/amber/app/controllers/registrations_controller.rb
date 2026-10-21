# frozen_string_literal: true

class RegistrationsController < ApplicationController
  include Shared::EmailRegistration
  unauthenticated_access_only only: %i[new create]
  skip_before_action :ensure_guest_user!, only: :create
  # brgen's UsersController#create — the same job in the other app — has carried
  # 10 per 10 minutes since it was written, and this one carried nothing: signup
  # is guest-reachable by definition, so an unlimited create is an unlimited
  # supply of accounts. Same numbers as brgen deliberately, because two signup
  # endpoints in one fleet disagreeing about the limit is how one of them gets
  # found.
  rate_limit to: 10, within: 10.minutes, only: :create, name: "signup",
    with: -> { redirect_to new_registration_path, alert: t("shared.flash.rate_limited") }

  def new = render

  def create
    unless signup_terms_accepted?
      render_signup_terms_error(registration_params)
      return
    end

    guest = persisted_guest_for_registration
    prepare_email_registration(registration_params)
    if @user.save
      send_signup_verification!(@user)
      merged = merge_registration_guest(@user, guest)
      if guest && !merged
        redirect_to root_path, alert: t("shared.email_verification.signup_guest_merge_failed")
        return
      end

      start_new_session_for @user
      notice_key = guest ? "shared.email_verification.signup_notice_guest_merged" : "shared.email_verification.signup_notice"
      redirect_to root_path, notice: t(notice_key, default: t("shared.email_verification.signup_notice"))
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
