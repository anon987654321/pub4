# frozen_string_literal: true

class CommunityMembershipsController < ApplicationController
  before_action :require_user_session

  def create
    community = Community.find(params[:community_id])
    if community.privacy == "private" && !community.member?(Current.user)
      redirect_to main_app.communities_path, alert: t("flash.community.members_only")
      return
    end
    Current.user.join_community!(community)
    redirect_back fallback_location: main_app.community_path(community), notice: t("community.joined", default: "Joined.")
  end

  def destroy
    # Scoped to Current.user's own membership — you only ever leave for yourself.
    membership = Current.user.community_memberships.find_by(community_id: params[:community_id])
    back = main_app.community_path(params[:community_id])
    # The last owner is refused: hand ownership on first, or the community has nobody to run it.
    if membership && !membership.destroy
      redirect_back fallback_location: back, alert: t("flash.community.last_owner_leaving")
      return
    end
    redirect_back fallback_location: back, notice: t("community.left", default: "Left.")
  end
end
