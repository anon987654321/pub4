# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :require_real_user

  def create
    # globalid ships locate_signed, not locate_signed! -- every report raised
    # NoMethodError. It returns nil rather than raising on a bad or expired
    # signature, so the nil case is handled here.
    @target = GlobalID::Locator.locate_signed(params.require(:target_gid))
    unless @target
      redirect_back fallback_location: root_path, alert: "That content is no longer available."
      return
    end

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
