# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  # brgen's UsersController#create — the same job in the other app — has carried
  # 10 per 10 minutes since it was written, and this one carried nothing: signup
  # is guest-reachable by definition, so an unlimited create is an unlimited
  # supply of accounts. Same numbers as brgen deliberately, because two signup
  # endpoints in one fleet disagreeing about the limit is how one of them gets
  # found.
  rate_limit to: 10, within: 10.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: t("shared.flash.rate_limited") }

  def new = render

  def create
    unless params[:accept_terms] == "1" && params[:accept_age] == "1"
      flash.now[:alert] = t("legal.accept_terms")
      render :new, status: :unprocessable_entity
      return
    end

    user = User.new(registration_params)
    if user.save
      start_new_session_for user
      redirect_to root_path, notice: t("flash.welcome")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
