# frozen_string_literal: true

class UsersController < ApplicationController
  include Shared::EmailRegistration
  allow_unauthenticated_access only: :show
  unauthenticated_access_only only: %i[new create]
  # Sign-up writes a user, not a guest row; minting a guest here would give
  # every newcomer a merge of nothing.
  skip_before_action :ensure_guest_user!, only: :create
  rate_limit to: 10, within: 10.minutes, only: :create, name: "signup",
    with: -> { redirect_to new_user_path, alert: t("shared.flash.rate_limited") }

  def show
    # By username as well as id, because the ActivityPub actor advertises
    # https://<city>/users/<username> as its `url` — and a profile link handed
    # to the fediverse that 404s in a browser is worse than not federating.
    scope = User.public_profiles.includes(:dating_profile)
    @user = scope.find_by(username: params[:id]) || scope.find(params[:id])
    load_posts
    @followers_count = @user.followers.count
    @following_count = @user.following.count
    @active_follow = authenticated? && Current.user.following?(@user)
    @active_block = authenticated? && Current.user != @user && Current.user.blocking?(@user)
    @activity = profile_activity
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
    return render :edit, status: :unprocessable_entity unless @user.update(profile_params)

    # Removing the photo brings the identicon back; touch, so the avatar
    # address (User#avatar_url) changes and no cached photo outlives it.
    if params.dig(:user, :remove_avatar) == "1" && @user.avatar.attached?
      @user.avatar.purge
      @user.touch
    end
    redirect_to main_app.user_path(@user), notice: t("profile.updated", default: "Profile updated.")
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

    unless signup_terms_accepted?
      render_signup_terms_error(user_params)
      return
    end

    guest = persisted_guest_for_registration
    prepare_email_registration(user_params)

    unless @user.save
      render :new, status: :unprocessable_entity
      return
    end

    # Send the confirmation email; the account exists but can't post under its
    # identity until it's verified (see ApplicationController#require_verified_email).
    send_signup_verification!(@user)

    merged = merge_registration_guest(@user, guest)
    if guest && !merged
      redirect_to after_authentication_url, alert: t("shared.email_verification.signup_guest_merge_failed")
      return
    end

    start_new_session_for @user
    redirect_to after_authentication_url, notice: t(guest ? "shared.email_verification.signup_notice_guest_merged" : "shared.email_verification.signup_notice")
  end

  private

  # Only what the profile may say this person wrote and this viewer may read:
  # no anonymous or Live posts, nothing removed, no private community the
  # viewer is not in. The preloads match HomeController's for the same card,
  # which reads post.image.attached? (one query per post without them).
  # The newest twenty this viewer may read, and how many there are in full:
  # the header counted the list, which stops at twenty.
  def load_posts
    readable = @user.posts.kept
    readable = readable.attributed.visible_to(Current.user)
    @posts_count = readable.count
    listed = readable.includes(:user, :community, :votes).with_attached_image
    @posts = listed.order(created_at: :desc).limit(20)
  end

  # The same rule for the activity list, which names the person beside each post.
  def profile_activity
    events = ActivityEvent.visible.public_only.readable_by(Current.user).attributable
    events.where(actor_id: @user.id).recent.limit(20)
  end

  def profile_params
    params.require(:user).permit(:username, :display_name, :bio, :avatar)
  end

  def user_params
    params.require(:user).permit(:email_address, :username, :password, :password_confirmation)
  end
end
