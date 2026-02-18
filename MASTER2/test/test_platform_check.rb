# frozen_string_literal: true

require_relative "test_helper"

class TestPlatformCheck < Minitest::Test
  def setup
    @original_platform = RUBY_PLATFORM
  end

  def test_openbsd_detection_via_ruby_platform
    skip "Only runs on OpenBSD" unless RUBY_PLATFORM.include?("openbsd")
    assert MASTER::PlatformCheck.openbsd?
  end

  def test_non_openbsd_detection
    skip "Only runs on non-OpenBSD" if RUBY_PLATFORM.include?("openbsd")
    # Should fall back to uname check
    result = MASTER::PlatformCheck.openbsd?
    # On Linux this should be false
    refute result unless `uname -s 2>/dev/null`.strip == "OpenBSD"
  end

  def test_bundler_available_when_installed
    # Bundler should be available if we're running tests
    assert MASTER::PlatformCheck.bundler_available?
  end

  def test_platform_in_lockfile_checks_gemfile_lock
    # Should return true if no lockfile exists or if ruby platform is present
    result = MASTER::PlatformCheck.platform_in_lockfile?
    assert [true, false].include?(result)
  end

  def test_diagnose_returns_array
    result = MASTER::PlatformCheck.diagnose
    assert_kind_of Array, result
  end

  def test_diagnose_returns_issue_hashes
    result = MASTER::PlatformCheck.diagnose
    result.each do |issue|
      assert_kind_of Hash, issue
      assert issue.key?(:problem)
      assert issue.key?(:fix)
      assert_kind_of String, issue[:problem]
      assert_kind_of String, issue[:fix]
    end
  end

  def test_print_diagnostics_returns_boolean
    result = MASTER::PlatformCheck.print_diagnostics
    assert [true, false].include?(result)
  end

  def test_print_diagnostics_returns_true_when_no_issues
    # Stub diagnose to return empty array
    MASTER::PlatformCheck.stub :diagnose, [] do
      assert MASTER::PlatformCheck.print_diagnostics
    end
  end

  def test_print_diagnostics_returns_false_when_issues_exist
    issues = [
      { problem: "Test problem", fix: "Test fix" }
    ]

    MASTER::PlatformCheck.stub :diagnose, issues do
      refute MASTER::PlatformCheck.print_diagnostics
    end
  end

  def test_openbsd_version_returns_nil_on_non_openbsd
    MASTER::PlatformCheck.stub :openbsd?, false do
      assert_nil MASTER::PlatformCheck.openbsd_version
    end
  end

  def test_openbsd_version_returns_string_on_openbsd
    skip "Only runs on OpenBSD" unless RUBY_PLATFORM.include?("openbsd")
    version = MASTER::PlatformCheck.openbsd_version
    assert_kind_of String, version
    refute_empty version
  end

  def test_summary_returns_nil_on_non_openbsd
    MASTER::PlatformCheck.stub :openbsd?, false do
      assert_nil MASTER::PlatformCheck.summary
    end
  end

  def test_summary_shows_all_checks_passed_when_no_issues
    MASTER::PlatformCheck.stub :openbsd?, true do
      MASTER::PlatformCheck.stub :diagnose, [] do
        MASTER::PlatformCheck.stub :openbsd_version, "7.8" do
          summary = MASTER::PlatformCheck.summary
          assert_includes summary, "OpenBSD 7.8"
          assert_includes summary, "all checks passed"
        end
      end
    end
  end

  def test_summary_shows_issue_count_when_issues_exist
    issues = [
      { problem: "Problem 1", fix: "Fix 1" },
      { problem: "Problem 2", fix: "Fix 2" }
    ]

    MASTER::PlatformCheck.stub :openbsd?, true do
      MASTER::PlatformCheck.stub :diagnose, issues do
        MASTER::PlatformCheck.stub :openbsd_version, "7.8" do
          summary = MASTER::PlatformCheck.summary
          assert_includes summary, "OpenBSD 7.8"
          assert_includes summary, "2 issue(s) found"
        end
      end
    end
  end

  def test_nokogiri_configured_checks_bundle_config
    result = MASTER::PlatformCheck.nokogiri_configured?
    assert [true, false].include?(result)
  end

  def test_system_headers_accessible_returns_true_on_non_openbsd
    MASTER::PlatformCheck.stub :openbsd?, false do
      assert MASTER::PlatformCheck.system_headers_accessible?
    end
  end

  def test_diagnose_includes_bundler_issue_when_not_available
    MASTER::PlatformCheck.stub :bundler_available?, false do
      MASTER::PlatformCheck.stub :openbsd?, false do
        MASTER::PlatformCheck.stub :platform_in_lockfile?, true do
          issues = MASTER::PlatformCheck.diagnose
          bundler_issue = issues.find { |i| i[:problem].include?("Bundler") }
          assert bundler_issue
          assert_includes bundler_issue[:fix], "gem install bundler"
        end
      end
    end
  end

  def test_diagnose_includes_nokogiri_issue_on_openbsd_when_not_configured
    MASTER::PlatformCheck.stub :bundler_available?, true do
      MASTER::PlatformCheck.stub :openbsd?, true do
        MASTER::PlatformCheck.stub :nokogiri_configured?, false do
          MASTER::PlatformCheck.stub :system_headers_accessible?, true do
            MASTER::PlatformCheck.stub :platform_in_lockfile?, true do
              issues = MASTER::PlatformCheck.diagnose
              nokogiri_issue = issues.find { |i| i[:problem].include?("Nokogiri") }
              assert nokogiri_issue
              assert_includes nokogiri_issue[:fix], "bundle config build.nokogiri"
            end
          end
        end
      end
    end
  end

  def test_diagnose_includes_platform_issue_when_not_in_lockfile
    MASTER::PlatformCheck.stub :bundler_available?, true do
      MASTER::PlatformCheck.stub :openbsd?, false do
        MASTER::PlatformCheck.stub :platform_in_lockfile?, false do
          issues = MASTER::PlatformCheck.diagnose
          platform_issue = issues.find { |i| i[:problem].include?("Gemfile.lock") }
          assert platform_issue
          assert_includes platform_issue[:fix], "bundle lock --add-platform ruby"
        end
      end
    end
  end

  def test_diagnose_returns_empty_when_all_checks_pass
    MASTER::PlatformCheck.stub :bundler_available?, true do
      MASTER::PlatformCheck.stub :openbsd?, false do
        MASTER::PlatformCheck.stub :platform_in_lockfile?, true do
          issues = MASTER::PlatformCheck.diagnose
          assert_empty issues
        end
      end
    end
  end
end
