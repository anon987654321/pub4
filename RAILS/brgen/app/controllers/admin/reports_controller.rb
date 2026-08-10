# frozen_string_literal: true

class Admin::ReportsController < ApplicationController
  before_action :require_admin!
  before_action :set_report, only: :update

  def index
    @pagy, @reports = pagy(ModerationReport.includes(:user, :reportable).recent)
    # One grouped COUNT, not a Ruby block count over every row: the block form
    # loaded the whole table to count it, and did so twice.
    by_status = ModerationReport.group(:status).count
    @open_count = by_status.fetch("open", 0)
    @reviewing_count = by_status.fetch("reviewing", 0)
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
