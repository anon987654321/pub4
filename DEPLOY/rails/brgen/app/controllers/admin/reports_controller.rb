# frozen_string_literal: true

class Admin::ReportsController < ApplicationController
  before_action :require_admin!
  before_action :set_report, only: :update

  def index
    @reports = ModerationReport.includes(:user, :reportable).recent
    @open_count = @reports.count { |report| report.status == "open" }
    @reviewing_count = @reports.count { |report| report.status == "reviewing" }
  end

  def update
    ModerationWorkflow.transition!(report: @report, status: params[:status]) if params[:status].present?
    redirect_back fallback_location: admin_reports_path
  end

  private

  def set_report
    @report = ModerationReport.find(params[:id])
  end

  def require_admin!
    return if Current.user&.email_address == ENV.fetch("BRGEN_ADMIN_EMAIL", "admin@brgen.no")

    redirect_to(root_path, alert: "Unauthorized")
  end
end
