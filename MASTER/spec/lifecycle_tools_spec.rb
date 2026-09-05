# frozen_string_literal: true

require "minitest/autorun"

class LifecycleToolsSpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read_tool(name)
    File.read(File.join(ROOT, "bin", name))
  end

  def test_doctor_reports_ok_fail_lines
    source = read_tool("doctor")
    assert_includes source, "MASTER doctor"
    assert_includes source, "OK"
    assert_includes source, "FAIL"
    assert_includes source, "check_yaml"
  end

  def test_smoke_web_waits_for_bootstrap
    source = read_tool("smoke-web")
    assert_includes source, "smoke-web"
    assert_includes source, "wait for bootstrap"
    assert_includes source, "MASTER_SMOKE_WEB_WARM_S"
    assert_includes source, "cache_efficiency"
  end

  def test_onboard_writes_master_config_yml
    source = read_tool("onboard")
    assert_includes source, "config.yml"
    assert_includes source, "--no-interactive"
    assert_includes source, "SecureRandom.hex"
  end

  def test_cleanup_is_dry_run_by_default
    source = read_tool("cleanup")
    assert_includes source, "dry-run only"
    assert_includes source, "--apply"
    assert_includes source, "working tree dirty"
  end

  def test_cleanup_writes_audit_reports
    source = read_tool("cleanup")
    assert_includes source, "reports"
    assert_includes source, "repo_inventory.rb"
    assert_includes source, "history_valuables.rb"
  end
end
