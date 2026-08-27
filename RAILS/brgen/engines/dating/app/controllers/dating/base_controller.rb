# frozen_string_literal: true

# What every dating surface needs to know: who the reader is on this vertical,
# and who they could be shown.
class Dating::BaseController < ApplicationController
  private

  # A profile is shown to strangers, so the account behind it has to be a
  # person. Vipps Login establishes that with a verified Norwegian phone
  # number, and it is the cheap half of the pair — Vipps MobilePay owns BankID,
  # but a BankID verification is billed per use and a Vipps Login is not.
  #
  # Nothing here fails closed on a misconfigured server: if VIPPS_CLIENT_ID is
  # absent the provider never registers, and gating on it would lock every
  # person out of a vertical for an operator's missing env var. When Vipps is
  # not configured this is not a check anyone can pass, so it is not a check.
  def require_vipps_identity
    return unless vipps_login_available?
    return if Current.user&.vipps_verified?

    redirect_to sign_in_path, alert: t("dating.vipps_required")
  end

  def vipps_login_available?
    Rails.application.config.x.oauth_provider_slugs.to_a.include?("vipps")
  end

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
