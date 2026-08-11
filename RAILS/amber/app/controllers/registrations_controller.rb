# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new = render

  def create
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
