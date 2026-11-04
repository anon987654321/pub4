# frozen_string_literal: true

class ReportsController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create,
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :require_real_user

  def create
    # globalid ships locate_signed, not locate_signed! -- every report raised
    # NoMethodError. It returns nil rather than raising on a bad or expired
    # signature, so the nil case is handled here.
    @target = GlobalID::Locator.locate_signed(params.require(:target_gid))
    unless @target
      redirect_back fallback_location: root_path, alert: t("flash.content_unavailable")
      return
    end

    @report = ModerationWorkflow.report!(
      reporter: Current.user,
      target: @target,
      # A reason outside the list is no reason, not a 500 from create!.
      reason: params[:reason].presence_in(ModerationReport::REASONS),
      details: params[:details].to_s.first(ModerationReport::DETAILS_LIMIT).presence
    )
    notify_moderators
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path, notice: t("flash.report_submitted") }
      f.turbo_stream
      f.json { render json: { reported: true } }
    end
  end

  private

  # A repeat of an open report tells the moderators nothing new.
  def notify_moderators
    return unless @report.previously_new_record?

    ModerationReportNotificationJob.perform_later(@report.id)
  end
end
