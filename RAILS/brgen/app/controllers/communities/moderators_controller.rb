# frozen_string_literal: true

# Appointing and removing moderators. Owner-only, deliberately: if a moderator
# could change roles, one could demote the person who made the community, and
# there is nothing above them to appeal to.
class Communities::ModeratorsController < ApplicationController
  before_action :require_user_session
  before_action :set_community
  before_action :require_owner!

  def index
    @memberships = @community.community_memberships.includes(:user).order(:role, :created_at)
  end

  def create
    membership = @community.community_memberships.find_by(user_id: params[:user_id])
    unless membership
      redirect_back fallback_location: community_moderators_path(@community),
                    alert: t("flash.community.not_a_member")
      return
    end

    membership.update!(role: "moderator")
    membership.deliver_notification(
      membership.user,
      title: t("community.moderator_appointed", community: @community.name),
      body: t("community.moderator_appointed_body"),
      source: @community
    )

    redirect_back fallback_location: community_moderators_path(@community),
                  notice: t("flash.community.moderator_added")
  end

  def destroy
    membership = @community.community_memberships.find(params[:id])
    if membership.update(role: "member")
      redirect_back fallback_location: community_moderators_path(@community),
                    notice: t("flash.community.moderator_removed")
    else
      # The last owner cannot be demoted — there would be nobody left who can
      # appoint anyone.
      redirect_back fallback_location: community_moderators_path(@community),
                    alert: membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_community
    @community = Community.find(params[:community_id])
  end

  def require_owner!
    return if @community.owner?(Current.user)

    redirect_to community_path(@community), alert: t("shared.flash.not_authorized")
  end
end
