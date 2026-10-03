# frozen_string_literal: true

# Weekly: clicks we sent, conversions that came back, and the gap.
#
# Logged rather than emailed, because the point is a line the operator can grep
# next to the deploy log — and because a report nobody schedules is a report
# nobody reads. See PartnerAttributionReport for what the three gap numbers mean.
class PartnerAttributionReportJob < ApplicationJob
  queue_as :bulk

  def perform(window_days: 7)
    report = PartnerAttributionReport.new(window: window_days.days).render
    report.each_line { |line| Rails.logger.info("[partner_attribution] #{line.rstrip}") }
    report
  end
end
