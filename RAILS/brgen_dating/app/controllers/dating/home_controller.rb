# frozen_string_literal: true

class Dating::HomeController < Dating::BaseController
  before_action :require_user_session, only: :next
  before_action :open_with_splash, only: :index

  STARTED_COOKIE = :dating_started

  def index
    # Guests browse + swipe immediately. Real users with a paused/missing
    # profile are nudged to complete it; guests are never forced to sign up.
    if authenticated?
      profile = current_dating_profile
      unless profile&.visible?
        redirect_to(profile ? edit_profile_path : new_profile_path)
        return
      end
    end
    # ranked_for, not RANDOM(): see Dating::Profile. The deck has to be
    # stable while someone browses, or a profile they just passed cannot be
    # found again.
    @profiles = candidate_scope.ranked_for(Current.user).limit(5)
    @next_profile = @profiles.first
    current_dating_profile&.touch_activity! if authenticated?
  end

  def next
    @profile = candidate_scope.ranked_for(Current.user).first
    head :no_content unless @profile
  end

  private

  # The first screen, once: "sveip for å begynne" leads here with ?start=1,
  # which remembers the reader has begun and drops the parameter, so a reload
  # or a shared link lands on the deck rather than on the intro again.
  def open_with_splash
    if params[:start].present?
      cookies.permanent[STARTED_COOKIE] = { value: "1", httponly: true, same_site: :lax }
      redirect_to root_path
    elsif cookies[STARTED_COOKIE].blank?
      render :splash
    end
  end
end
