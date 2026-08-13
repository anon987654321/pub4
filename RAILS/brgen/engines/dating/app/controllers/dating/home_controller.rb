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

  private

  def current_dating_profile
    return nil unless Current.user

    @current_dating_profile ||= Dating::Profile.find_by(user_id: Current.user.id)
  end

  def candidate_scope
    # joins(:user) drops orphan profiles (visible but user deleted) that crash the card.
    scope = Dating::Profile.visible.joins(:user).includes(:user, :neighborhood, photos_attachments: :blob)
    return scope unless Current.user.present?

    profile = current_dating_profile
    liked_ids = Dating::Like.where(liker_id: Current.user.id).pluck(:likee_id)
    disliked_ids = Dating::Dislike.where(disliker_id: Current.user.id).pluck(:dislikee_id)
    excluded = (liked_ids + disliked_ids + [ Current.user.id ]).uniq
    scope = scope.where.not(user_id: excluded)
    # Orientation: mutual gender preference, so it's a dating app rather than a
    # random-person feed. See Dating::Profile.oriented_for.
    scope = scope.oriented_for(profile) if profile
    if (neigh = profile&.neighborhood)
      scope = scope.in_neighborhood(neigh)
    end
    if profile&.latitude && profile&.longitude
      scope = scope.nearby(profile.latitude, profile.longitude, 20)
    end
    scope
  end
end
