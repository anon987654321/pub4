# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :require_real_user

  def create
    @target = GlobalID::Locator.locate_signed!(params.require(:target_gid))
    @report = ModerationWorkflow.report!(
      reporter: Current.user,
      target: @target,
      reason: params[:reason],
      details: params[:details]
    )
    ModerationReportNotificationJob.perform_later(@report.id)
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path, notice: "Report submitted." }
      f.turbo_stream
      f.json { render json: { reported: true } }
    end
  end
end
