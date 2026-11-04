# frozen_string_literal: true

require "test_helper"

class CspNonceTest < ActionDispatch::IntegrationTest
  def nonce
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    header.to_s[/'nonce-([^']*)'/, 1]
  end

  test "every response carries a fresh, non-blank script nonce" do
    get root_path
    first = nonce
    get root_path

    assert first.present?, "the first visit must not get an empty nonce"
    assert_not_equal first, nonce
    assert_includes response.body, %(nonce="#{nonce}")
  end
  test "violations are reported to the app and logged" do
    get root_path
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    assert_includes header, "report-uri /csp-reports"

    log = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    report = { "csp-report" => { "violated-directive" => "script-src", "blocked-uri" => "inline", "cookie" => "x" } }
    post csp_reports_path, params: report.to_json, headers: { "CONTENT_TYPE" => "application/csp-report" }
    Rails.logger = previous

    assert_response :no_content
    assert_includes log.string, %("violated-directive":"script-src")
    assert_not_includes log.string, "cookie"
  end
end
