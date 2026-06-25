# frozen_string_literal: true

class Dating::HomeController < Dating::BaseController
  def index
    if authenticated?
      profile = current_dating_profile
      unless profile&.visible?
        redirect_to(profile ? edit_dating_profile_path : new_dating_profile_path)
        return
      end
    end
    @profiles = candidate_scope.order(Arel.sql("RANDOM()")).limit(5)
    @next_profile = candidate_scope.order(Arel.sql("RANDOM()")).first
  end

  def next
    return require_real_user unless authenticated?

    @profile = candidate_scope.order(Arel.sql("RANDOM()")).first
    head :no_content unless @profile
  end

  private

  def current_dating_profile
    @current_dating_profile ||= Dating::Profile.find_by(user_id: Current.user.id)
  end

  def candidate_scope
    scope = Dating::Profile.visible.includes(:user, :neighborhood, photos_attachments: :blob)
    return scope unless authenticated?

    profile = current_dating_profile
    liked_ids = Dating::Like.where(liker_id: Current.user.id).pluck(:likee_id)
    disliked_ids = Dating::Dislike.where(disliker_id: Current.user.id).pluck(:dislikee_id)
    excluded = (liked_ids + disliked_ids + [Current.user.id]).uniq
    scope = scope.where.not(user_id: excluded)
    if (neigh = profile&.neighborhood)
      scope = scope.in_neighborhood(neigh)
    end
    if profile&.latitude && profile&.longitude
      scope = scope.nearby(profile.latitude, profile.longitude, 20)
    end
    scope
  end
end