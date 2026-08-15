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
    expected = ENV["BRGEN_ADMIN_EMAIL"].to_s.strip
    if expected.present? && Current.user&.email_address == expected
      return if !Current.user.respond_to?(:email_verified?) || Current.user.email_verified?
    end

    redirect_to(root_path, alert: t("shared.flash.not_authorized"))
  end
end
