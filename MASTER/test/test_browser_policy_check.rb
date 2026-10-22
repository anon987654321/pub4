# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../checks/support/check_result"

module Master
  ROOT = File.expand_path("..", __dir__) unless const_defined?(:ROOT, false)
end

require_relative "../checks/lib/source/browser_policy"

class TestBrowserPolicyCheck < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_check_returns_a_result_without_masking_an_internal_exception
    result = Deploy::BrowserPolicyCheck.run

    assert_instance_of Deploy::CheckResult, result
    refute result.errored?, result.errors.join("\n")
  end

  def test_check_does_not_require_master_runtime_root
    master_root = Master.send(:remove_const, :ROOT)
    result = Deploy::BrowserPolicyCheck.run

    assert_equal :passed, result.outcome, result.inspect
  ensure
    Master.const_set(:ROOT, master_root) if master_root && !Master.const_defined?(:ROOT, false)
  end
  def test_check_uses_instance_result_methods_not_missing_class_factories
    source = File.read(File.join(ROOT, "checks/lib/source/browser_policy.rb"))
    refute_includes source, "root = Master::ROOT"

    refute_match(/\bCheckResult\.(?:fail|pass)\s*\(/, source)
  end

  def test_check_enforces_session_browser_capabilities
    policy = YAML.safe_load_file(File.join(ROOT, "data/laws.yml"), aliases: true).fetch("browser_policy")
    assert_equal %w[status navigate login extract look follow paginate close], policy.fetch("read_actions")
    assert_equal true, policy.fetch("session_host_bound")
    assert_equal true, policy.fetch("screenshot_evidence_required")
    assert_equal 500, policy.fetch("max_capture_files")
    assert_equal 50, policy.fetch("max_pagination_pages")
    assert_equal 131_072, policy.fetch("max_pagination_output_bytes")
    assert_equal true, policy.fetch("follow_anchors_by_href_only")
    assert_equal "blocked", policy.fetch("visible_login_submission")

    result = Deploy::BrowserPolicyCheck.run
    assert_equal :passed, result.outcome, result.inspect
  end
end
