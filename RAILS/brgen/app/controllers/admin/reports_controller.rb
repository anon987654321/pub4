# frozen_string_literal: true

class Admin::ReportsController < ApplicationController
  include AdminAccess

  before_action :require_admin!
  before_action :set_report, only: :update

  FILTERS = (ModerationReport::STATUSES + %w[all]).freeze

  def index
    # Open by default: the queue is the work still to do, and a moderator who
    # wants the history asks for it by status or for all of them.
    @status = FILTERS.include?(params[:status]) ? params[:status] : "open"
    scope = ModerationReport.includes(:user, :reportable).recent
    scope = scope.where(status: @status) unless @status == "all"
    @pagy, @reports = pagy(scope)
    # A reported comment links to its post; load those posts in one query.
    comments = @reports.map(&:reportable).grep(Comment)
    ActiveRecord::Associations::Preloader.new(records: comments, associations: :commentable).call if comments.any?
    # One grouped COUNT, not a Ruby block count over every row: the block form
    # loaded the whole table to count it, and did so twice.
    by_status = ModerationReport.group(:status).count
    @open_count = by_status.fetch("open", 0)
    @reviewing_count = by_status.fetch("reviewing", 0)
  end

  def update
    ModerationWorkflow.transition!(report: @report, status: params[:status], decision_reason: params[:decision_reason]) if params[:status].present?
    redirect_back fallback_location: admin_reports_path
  end

  private

  def set_report
    @report = ModerationReport.find(params[:id])
  end
end
