# frozen_string_literal: true

require "test_helper"

# The report-only policy asks for Trusted Types, so the browser reports every
# innerHTML-style sink (link_preview, offline_page, optimistic_send) to
# /csp-reports before anyone turns enforcement on. It never rides in an
# enforced policy: there it would break those sinks today.
class TrustedTypesReportTest < ActionDispatch::IntegrationTest
  test "the report-only policy requires trusted types for scripts" do
    host! "brgen.no"
    get "/privacy"

    assert_response :success
    report_only = response.headers["Content-Security-Policy-Report-Only"].to_s
    assert_includes report_only, "require-trusted-types-for 'script'"
    assert_includes report_only, "report-uri /csp-reports"
    assert_nil response.headers["Content-Security-Policy"], "the test environment does not enforce"
  end
end
