# frozen_string_literal: true

class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[show new create]
  rate_limit to: 10, within: 10.minutes, only: :create,
    with: -> { redirect_to new_user_path, alert: "Try again later." }

  def show
    @user = User.includes(:dating_profile).find(params[:id])
    @posts = @user.posts.includes(:community, :votes).order(created_at: :desc).limit(20)
    @followers_count = @user.followers.count
    @following_count = @user.following.count
    @active_follow = authenticated? && Current.user.following?(@user)
  end

  def new
    @user = User.new
  end

  # The anonymous quota wall says "Sign up to post more" and sends the visitor
  # to sign-in, but there was no way to create an account at all: OAuth buttons
  # only render for providers configured in the environment, and no
  # registration action existed. This is that missing door.
  def create
    @user = User.new(user_params)
    @user.guest = false
    guest = Current.user if Current.user&.guest?

    unless @user.save
      render :new, status: :unprocessable_entity
      return
    end

    merge_guest_into(@user, guest)
    start_new_session_for @user
    redirect_to after_authentication_url, notice: "Welcome to Brgen."
  end

  private

  # Carry the guest's posts, comments and conversations onto the new account.
  # Must run before start_new_session_for, which resets the session holding the
  # guest id. A failed merge must not cost the visitor the account they just
  # made, so it is logged rather than raised.
  def merge_guest_into(user, guest)
    return unless guest

    AccountMerger.new(guest_user: guest, user: user).call
  rescue StandardError => error
    Rails.logger.warn("guest merge on signup failed: #{error.message}")
  end

  def user_params
    params.require(:user).permit(:email_address, :username, :password, :password_confirmation)
  end
end
