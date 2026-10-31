# frozen_string_literal: true

# What every dating surface needs to know: who the reader is on this vertical,
# and who they could be shown.
class Dating::BaseController < ApplicationController
  private

  # A profile is shown to strangers, so the account behind it has to be a
  # person. A verified identity proves it: Vipps Login (a verified Norwegian
  # phone number) or BankID at LOA 4, both of which OmniauthCallbacksController
  # records as assurance "verified". Vipps MobilePay owns BankID; BankID is billed
  # per use and a Vipps Login is not, so either is accepted where configured.
  #
  # The gate fails closed. With a verifier configured, only a verified account
  # passes. Without one the writing surfaces lock until the operator sets
  # DATING_IDENTITY_BYPASS=demo in env: a named, visible decision, never the
  # absence of keys. It used to open for everyone once Vipps was configured,
  # because "Vipps is available" was read as "the verification ran".
  def require_verified_identity
    return if Current.user&.identity_verified?
    return if identity_bypassed?

    redirect_to sign_in_path, alert: t("dating.vipps_required")
  end

  IDENTITY_PROVIDERS = { "bankid" => "BankID", "vipps" => "Vipps" }.freeze

  # The provider the gate asks for, BankID first: the one the first screen names.
  def identity_provider_name
    slugs = Rails.application.config.x.oauth_provider_slugs.to_a
    IDENTITY_PROVIDERS.find { |slug, _name| slugs.include?(slug) }&.last
  end
  helper_method :identity_provider_name

  def identity_bypassed?
    identity_provider_name.nil? && ENV["DATING_IDENTITY_BYPASS"].to_s.strip == "demo"
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
    # NOT EXISTS rather than plucked ids: someone who has swiped for a year would
    # otherwise send every answer back to the database as a literal list.
    profile_user_id = Dating::Profile.arel_table[:user_id]
    liked = Dating::Like.where(liker_id: Current.user.id).where(Dating::Like.arel_table[:likee_id].eq(profile_user_id))
    disliked = Dating::Dislike.where(disliker_id: Current.user.id).where(Dating::Dislike.arel_table[:dislikee_id].eq(profile_user_id))
    scope = scope.where.not(user_id: Current.user.id).where(liked.arel.exists.not).where(disliked.arel.exists.not)
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
