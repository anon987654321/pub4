# frozen_string_literal: true

class Dating::HomeController < Dating::BaseController
  def index
    profile = Current.user.dating_profile
    unless profile&.visible?
      redirect_to edit_dating_profile_path and return
    end
    liked_ids    = Dating::Like.where(liker: Current.user).pluck(:likee_id)
    disliked_ids = Dating::Dislike.where(disliker: Current.user).pluck(:dislikee_id)
    excluded     = (liked_ids + disliked_ids + [Current.user.id]).uniq
    @pagy, @profiles = pagy(
      Dating::Profile.visible
        .where.not(user_id: excluded)
        .includes(:user)
        .order(Arel.sql("RANDOM()"))
    )
  end
end
