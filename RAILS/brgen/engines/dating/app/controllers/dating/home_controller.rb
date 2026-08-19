# frozen_string_literal: true

class Dating::HomeController < Dating::BaseController
  before_action :require_user_session, only: :next

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
end
