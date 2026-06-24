# frozen_string_literal: true

class Dating::HomeController < Dating::BaseController
  def index
    unless Current.user.dating_profile&.visible?
      redirect_to edit_dating_profile_path
      return
    end
    @profiles = candidate_scope.order(Arel.sql("RANDOM()")).limit(5)
    @next_profile = candidate_scope.order(Arel.sql("RANDOM()")).first
  end

  def next
    @profile = candidate_scope.order(Arel.sql("RANDOM()")).first
    head :no_content unless @profile
  end

  private

  def candidate_scope
    profile = Current.user.dating_profile
    liked_ids    = Dating::Like.where(liker: Current.user).pluck(:likee_id)
    disliked_ids = Dating::Dislike.where(disliker: Current.user).pluck(:dislikee_id)
    excluded     = (liked_ids + disliked_ids + [ Current.user.id ]).uniq
    scope = Dating::Profile.visible.where.not(user_id: excluded).includes(:user)
    if (neigh = profile&.neighborhood)
      scope = scope.in_neighborhood(neigh)
    end
    if profile&.latitude && profile&.longitude
      scope = scope.nearby(profile.latitude, profile.longitude, 20)
    end
    scope
  end
end
