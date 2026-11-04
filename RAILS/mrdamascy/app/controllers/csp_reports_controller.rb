# frozen_string_literal: true

# Where browsers send Content-Security-Policy violations (the policy's
# report-uri), so the report-only policy shows what enforcement would
# break before MRDAMASCY_CSP_ENFORCE flips it on. Each report is one log
# line; the body is the browser's, so only its known fields are kept.
class CspReportsController < ApplicationController
  # Browsers post reports without a form token or a session.
  skip_forgery_protection

  # A page full of violations sends one report each; a flood is not data.
  rate_limit to: 60, within: 1.minute, name: "csp_reports", with: -> { head :too_many_requests }

  REPORT_FIELDS = %w[document-uri violated-directive effective-directive blocked-uri source-file line-number].freeze

  def create
    report = JSON.parse(request.raw_post).fetch("csp-report", {})
    Rails.logger.warn("[csp] #{report.slice(*REPORT_FIELDS).to_json}") if report.is_a?(Hash)
    head :no_content
  rescue JSON::ParserError
    head :bad_request
  end
end
