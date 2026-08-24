# frozen_string_literal: true

# The reader for `policy.report_uri "/csp-reports"`.
#
# The policy was report-only with no report_uri for its whole life, so every
# violation was neither blocked nor recorded — a header that cost bytes on every
# response and told nobody anything. Logging is the whole job: the point of
# report-only is to find out what enforcement would break before turning it on.
class CspReportsController < ActionController::API
  # Browsers post these unauthenticated, cross-origin, with no CSRF token and
  # with content-type application/csp-report.
  skip_forgery_protection if respond_to?(:skip_forgery_protection)

  MAX_BYTES = 8_192

  def create
    body = request.body.read(MAX_BYTES).to_s
    return head :bad_request if body.empty?

    report = (JSON.parse(body)["csp-report"] rescue nil)
    return head :bad_request unless report.is_a?(Hash)

    # Four fields, not the whole document. A blocked-uri can carry a full URL
    # with query string, and this endpoint takes anything anyone posts to it.
    Rails.logger.warn(
      "csp_violation directive=#{report['violated-directive'].to_s.first(120)} " \
      "blocked=#{report['blocked-uri'].to_s.first(200)} " \
      "document=#{report['document-uri'].to_s.first(200)} " \
      "line=#{report['line-number']}"
    )
    head :no_content
  end
end
