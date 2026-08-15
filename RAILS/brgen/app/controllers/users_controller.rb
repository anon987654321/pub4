# frozen_string_literal: true

class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[show new create]
  rate_limit to: 10, within: 10.minutes, only: :create,
    with: -> { redirect_to new_user_path, alert: t("shared.flash.rate_limited") }

  def show
    # By username as well as id, because the ActivityPub actor advertises
    # https://<city>/users/<username> as its `url` — and a profile link handed
    # to the fediverse that 404s in a browser is worse than not federating.
    scope = User.includes(:dating_profile)
    @user = scope.find_by(username: params[:id]) || scope.find(params[:id])
    @posts = @user.posts.includes(:community, :votes).order(created_at: :desc).limit(20)
    @followers_count = @user.followers.count
    @following_count = @user.following.count
    @active_follow = authenticated? && Current.user.following?(@user)
    @active_block  = authenticated? && Current.user != @user && Current.user.blocking?(@user)
    @activity = ActivityEvent.visible.public_only.where(actor_id: @user.id).recent.limit(20)
    @stores = @user.marketplace_stores.active.limit(8)
    @casual_listings = @user.marketplace_listings.live.casual.limit(8)
    @restaurants = @user.takeaway_restaurants.active.limit(8)
    @channels = @user.tv_channels.limit(8)
    @playlists = @user.playlist_playlists.public_playlists.limit(8)
  end

  # Edit/update your own profile — always Current.user, never someone else's row.
  def edit
    require_user_session
    @user = Current.user
  end

  def update
    require_user_session
    @user = Current.user
    if @user.update(profile_params)
      redirect_to main_app.user_path(@user), notice: t("profile.updated", default: "Profile updated.")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def new
    @user = User.new
  end

  # The anonymous quota wall says "Sign up to post more" and sends the visitor
  # to sign-in, but there was no way to create an account at all: OAuth buttons
  # only render for providers configured in the environment, and no
  # registration action existed. This is that missing door.
  def create
    # Honeypot: a hidden field no human ever fills. A bot that fills it gets a
    # success-looking response and no account — cheap defence with no CAPTCHA.
    if params[:homepage].present?
      redirect_to after_authentication_url, notice: t("flash.welcome")
      return
    end

    unless params[:accept_terms] == "1" && params[:accept_age] == "1"
      @user = User.new(user_params)
      @user.errors.add(:base, t("legal.accept_terms"))
      render :new, status: :unprocessable_entity
      return
    end

    @user = User.new(user_params)
    @user.guest = false
    @user.require_email_verification = true # a public signup must confirm before posting
    guest = Current.user if Current.user&.guest?

    unless @user.save
      render :new, status: :unprocessable_entity
      return
    end

    # Send the confirmation email; the account exists but can't post under its
    # identity until it's verified (see ApplicationController#require_verified_email).
    @user.generate_email_verification!
    VerificationMailer.verify(@user).deliver_later

    merged = merge_guest_into(@user, guest)
    start_new_session_for @user
    notice =
      if merged
        "Welcome to Brgen — your guest posts and chats are on this account."
      else
        "Welcome to Brgen."
      end
    redirect_to after_authentication_url, notice: notice
  end

  private

  # Carry the guest's posts, comments and conversations onto the new account.
  # Must run before start_new_session_for, which resets the session holding the
  # guest id. A failed merge must not cost the visitor the account they just
  # made, so it is logged rather than raised. Returns true when a merge ran.
  def merge_guest_into(user, guest)
    return false unless guest

    AccountMerger.new(guest_user: guest, user: user).call
    true
  rescue StandardError => error
    Rails.logger.warn("guest merge on signup failed: #{error.message}")
    false
  end

  def profile_params
    params.require(:user).permit(:username, :display_name)
  end

  def user_params
    params.require(:user).permit(:email_address, :username, :password, :password_confirmation)
  end
end
