# frozen_string_literal: true

require_relative "test_helper"

class TestSecurityAudit < Minitest::Test
  def test_report_is_clean_on_this_tree
    report = Master::Ground::SecurityAudit.report
    assert_includes report, "security-audit: clean", report
    assert_includes report, "pairing-required"
    assert_includes report, "visitor-slash"
    assert_includes report, "public-profile"
    refute_includes report, "FAIL"
  end

  def test_public_and_messaging_profiles_exclude_shell
    checks = Master::Ground::SecurityAudit.checks
    public = checks.find { |row| row.name == "public-profile" }
    messaging = checks.find { |row| row.name == "messaging-profile" }
    assert public.ok, public.detail
    assert messaging.ok, messaging.detail
    refute_includes public.detail, "Shell"
    refute_includes messaging.detail, "Shell"
  end
end
