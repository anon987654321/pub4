# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/configuration_guard"
require_relative "../lib/ground/boot_checks"

class TestLimitsCatalogueGuard < Minitest::Test
  Guard = Master::ConfigurationGuard
  BootChecks = Master::Ground::BootChecks

  def limits_path
    File.join(Master::ROOT, "data", "limits.yml")
  end

  def load_live_limits
    YAML.safe_load_file(limits_path, aliases: true)
  end

  def test_live_limits_catalogue_satisfies_its_schema
    assert_nil Guard.validate(path: limits_path, content: File.read(limits_path, encoding: "UTF-8"))
  end

  def test_unknown_top_level_fields_are_rejected
    data = load_live_limits
    data["unexpected_budget_section"] = {}

    reason = Guard.validate(path: limits_path, content: YAML.dump(data))

    assert_match(/limits\.yml has unknown top-level field\(s\): unexpected_budget_section/, reason)
  end

  def test_scan_profile_must_reference_a_declared_law_group
    data = load_live_limits
    data.fetch("scan_profiles").fetch("full")["laws"] = "missing_law_group"

    reason = Guard.validate(path: limits_path, content: YAML.dump(data))

    assert_match(/scan_profiles\.full\.laws must be '\*' or reference a declared law group/, reason)
  end

  def test_session_mode_must_reference_a_declared_scan_profile
    data = load_live_limits
    data.fetch("session_modes").fetch("modes").fetch("strict")["scan_profile"] = "missing_profile"

    reason = Guard.validate(path: limits_path, content: YAML.dump(data))

    assert_match(/session_modes\.modes\.strict\.scan_profile must reference a declared profile/, reason)
  end

  def test_host_specific_resource_thresholds_are_checked_as_rows
    data = load_live_limits
    data.fetch("process").fetch("resources").fetch("process_count").fetch("darwin")["warn"] = "too high"

    reason = Guard.validate(path: limits_path, content: YAML.dump(data))

    assert_match(/process\.resources\.process_count\.darwin\.warn must be positive numeric/, reason)
  end

  def test_canonical_boot_runs_limits_schema_validation
    result = BootChecks.send(:check_limits_yaml, Master::ROOT)

    assert result.ok, result.message
    assert_match(/schema and references valid/, result.message)
  end

  def test_boot_rejects_an_invalid_limits_catalogue_before_startup
    Dir.mktmpdir("master-limits-catalogue-boot") do |tmp|
      root = File.join(tmp, "MASTER")
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      data = load_live_limits
      data.fetch("session_modes")["default"] = "missing_mode"
      File.write(File.join(data_dir, "limits.yml"), YAML.dump(data))

      result = BootChecks.send(:check_limits_yaml, root)

      refute result.ok
      assert_equal :fatal, result.severity
      assert_match(/session_modes\.default must name a declared mode/, result.message)
    end
  end
end
