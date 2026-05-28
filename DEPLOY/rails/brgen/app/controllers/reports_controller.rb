# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :require_real_user

  def create
    @target = GlobalID::Locator.locate_signed!(params.require(:target_gid))
    @report = ModerationReport.create!(
      user: Current.user,
      reportable: @target,
      reason: params[:reason].presence || "other",
      status: "open"
    )
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path, notice: "Report submitted." }
      f.turbo_stream
      f.json { render json: { reported: true } }
    end
  end
end
