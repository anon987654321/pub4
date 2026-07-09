# frozen_string_literal: true

class ModerationReportNotificationJob < ApplicationJob
  queue_as :default

  def perform(report_id)
    report = ModerationReport.find_by(id: report_id)
    return unless report

    admin = User.find_by(email_address: ENV.fetch("BRGEN_ADMIN_EMAIL", "admin@brgen.no"))
    return unless admin

    Notification.create!(
      user: admin,
      actor: report.user,
      kind: "custom",
      title: "New moderation report",
      body: "#{report.reason} on #{report.reportable_type}##{report.reportable_id}",
      notifiable: report
    )
  end
end
