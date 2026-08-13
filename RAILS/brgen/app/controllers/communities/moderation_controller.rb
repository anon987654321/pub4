# frozen_string_literal: true

# The queue a community's own moderators work, as opposed to Admin::Reports,
# which is every report in the app behind a single BRGEN_ADMIN_EMAIL check.
#
# ModerationReport is polymorphic and carries no community_id, so this derives
# the queue from the posts and comments that belong here rather than
# denormalising a column that would then need backfilling and keeping true.
class Communities::ModerationController < ApplicationController
  before_action :require_user_session
  before_action :set_community
  before_action :require_moderator!

  def index
    @pagy, @reports = pagy(@community.moderation_queue.includes(:user, :reportable))
    by_status = @community.moderation_queue.group(:status).count
    @open_count = by_status.fetch("open", 0)
    @reviewing_count = by_status.fetch("reviewing", 0)
  end

  def update
    report = @community.moderation_queue.find(params[:id])
    ModerationWorkflow.transition!(report: report, status: params[:status]) if params[:status].present?
    redirect_back fallback_location: community_moderation_index_path(@community)
  end

  private

  def set_community
    @community = Community.find(params[:community_id])
  end

  def require_moderator!
    return if @community.moderator?(Current.user) || @community.owner?(Current.user)

    redirect_to community_path(@community), alert: t("shared.flash.not_authorized")
  end
end
