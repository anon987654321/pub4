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
  # The edit form asks as the person types, after a pause; this bounds a script.
  rate_limit to: 60, within: 1.minute, only: :username_availability, name: "username_availability"

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

  # Newest first, with the preloads HomeController uses for the same card,
  # which reads post.image.attached? (one query per post without them).
  # Shared with the reflex, so page two follows from page one.
  def self.profile_page_scope(readable)
    cards = readable.includes(:user, :community, :votes)
    # images too: the card's media block reads post.images.attached?, which
    # an image-only preload still paid one query per post on every profile.
    cards.with_attached_image.with_attached_images.order(created_at: :desc)
  end

  def update
    require_user_session
    @user = Current.user
    @user.assign_attributes(profile_params)
    return render :edit, status: :unprocessable_entity unless @user.save(context: :profile)

    # Removing the photo brings the identicon back; touch, so the avatar
    # address (User#avatar_url) changes and no cached photo outlives it.
    if params.dig(:user, :remove_avatar) == "1" && @user.avatar.attached?
      @user.avatar.purge
      @user.touch
    end
    redirect_to main_app.user_path(@user), notice: t("profile.updated", default: "Profile updated.")
  end

  # The edit form's live hint: whether the typed name is free for this person,
  # as the sentence the form shows, so the rule is worded in one place.
  def username_availability
    require_user_session
    return if performed?

    name = params[:username].to_s.strip
    available = Current.user.username_available?(name)
    limits = { min: User::USERNAME_LENGTH.min, max: User::USERNAME_LENGTH.max }
    message = t("profile.username_#{availability_key(name, available)}", name:, **limits)
    render json: { available:, message: }
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

  # The first page of what this viewer may read (User#readable_posts_for),
  # and how many there are in full for the header. Later pages come from
  # ProfilePostsInfiniteScrollReflex, which pages the same scope.
  def load_posts
    readable = @user.readable_posts_for(Current.user)
    @posts_count = readable.count
    @pagy, @posts = pagy(self.class.profile_page_scope(readable))
  end

  # The same rule for the activity list, which names the person beside each post.
  def profile_activity
    events = ActivityEvent.visible.public_only.readable_by(Current.user).attributable
    events.where(actor_id: @user.id).recent.limit(20)
  end

  def availability_key(name, available)
    return "available" if available

    User.username_well_formed?(name) ? "taken" : "invalid"
  end

  def profile_params
    params.require(:user).permit(:username, :display_name, :bio, :avatar)
  end

  def user_params
    params.require(:user).permit(:email_address, :username, :password, :password_confirmation)
  end
end
