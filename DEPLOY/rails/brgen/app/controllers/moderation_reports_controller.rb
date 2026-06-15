# frozen_string_literal: true

class ModerationReportsController < ApplicationController
  before_action :require_real_user

  def index
    @reports = ModerationReport.where(status: "open").order(created_at: :desc).limit(100)
  end

  def bulk_update
    ids = Array(params[:report_ids]).map(&:to_i)
    ModerationReport.where(id: ids).update_all(status: params[:status].presence || "dismissed")
    redirect_to moderation_reports_path, notice: "Reports updated."
  end
end