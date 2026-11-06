# frozen_string_literal: true

class CommunityMembershipsController < ApplicationController
  before_action :require_user_session
  before_action :set_community, :refuse_outsider_of_private, :refuse_banned, only: :create

  # Over Turbo, the button and the member count change in place; without it,
  # the page reloads with a flash, as before.
  def create
    Current.user.join_community!(@community)
    respond_in_place(joined: true, notice: t("community.joined"))
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
    @community = Community.find_by(id: params[:community_id])
    return redirect_back(fallback_location: back, notice: t("community.left")) unless @community

    respond_in_place(joined: false, notice: t("community.left"))
  end

  private

  def respond_in_place(joined:, notice:)
    @community.reload
    @joined = joined
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_back fallback_location: main_app.community_path(@community), notice: }
    end
  end

  def set_community
    @community = Community.find(params[:community_id])
  end

  def refuse_outsider_of_private
    return unless @community.privacy == "private" && !@community.member?(Current.user)

    redirect_to main_app.communities_path, alert: t("flash.community.members_only")
  end

  # A ban stops posting; leaving and rejoining must not lift it.
  def refuse_banned
    return unless @community.banned?(Current.user)

    redirect_back fallback_location: main_app.community_path(@community), alert: t("community.join_banned")
  end
end
