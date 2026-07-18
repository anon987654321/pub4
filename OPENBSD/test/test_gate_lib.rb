# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/gate_result"
require_relative "../lib/gate_environment"

class GateLibTest < Minitest::Test
  def test_gate_result_tracks_failures_and_warnings
    result = Deploy::GateResult.new
    assert result.ok?

    result.warn("heads up")
    assert result.ok?

    result.fail("blocked")
    refute result.ok?
    assert_equal ["blocked"], result.failures
    assert_equal ["heads up"], result.warnings
  end

  def test_gate_result_report_exits_on_failure
    result = Deploy::GateResult.new
    result.fail("nope")

    assert_raises(SystemExit) { result.report!("should not print") }
  end

  def test_integrity_gates_include_expected_entries
    names = Deploy::GateEnvironment::INTEGRITY_GATES.map(&:name)

    %w[
      deploy_identity
      production
      phantom_fk
      frontend
      relayd_smoke
      domain_align
      crawl_inventory
      schema_migration
      asset_freshness
      human_walkthrough
      vps_health
    ].each do |expected|
      assert_includes names, expected, "missing gate #{expected}"
    end
  end

  def test_vps_health_gate_targets_core_health_check
    gate = Deploy::GateEnvironment::INTEGRITY_GATES.find { |entry| entry.name == "vps_health" }
    refute_nil gate
    assert_equal "OPENBSD/health_check.rb", gate.path
    assert_equal ["--core"], gate.args
    assert_includes gate.needs, :vps
  end
end