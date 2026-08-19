# frozen_string_literal: true

# What every dating surface needs to know: who the reader is on this vertical,
# and who they could be shown.
class Dating::BaseController < ApplicationController
  private

  def current_dating_profile
    return nil unless Current.user

    @current_dating_profile ||= Dating::Profile.find_by(user_id: Current.user.id)
  end

  # Hoisted out of HomeController when the daily picks became a second reader.
  # Two copies of "who may this person be shown" is two places for orientation
  # or a block to stop being honoured.
  def candidate_scope
    # joins(:user) drops orphan profiles (visible but user deleted) that crash the card.
    scope = Dating::Profile.visible.with_photos.joins(:user).includes(:user, :neighborhood, :prompts, photos_attachments: :blob)
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
