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

  # measured_nothing? separates "declined to measure" from "measured and passed".
  # A result that recorded nothing at all is a pass: it made no claim either way.
  def test_measured_nothing_distinguishes_a_skip_from_a_check
    assert_equal :passed, Deploy::GateResult.new.outcome

    skipped = Deploy::GateResult.new.inconclusive!("no Chrome")
    assert skipped.measured_nothing?
    assert_equal :inconclusive, skipped.outcome

    partial = Deploy::GateResult.new.inconclusive!("no Chrome").checked!(3)
    refute partial.measured_nothing?, "a gate that ran three checks measured something"
    assert_equal :passed, partial.outcome

    live = Deploy::GateResult.new.skipped_live("port 61352 closed")
    assert live.measured_nothing?, "every live check skipped is nothing measured"
  end

  def test_skip_reason_consults_the_needs_it_declares
    vps_gate = Deploy::GateEnvironment::Gate.new(name: "x", path: "y", needs: %i[vps])
    plain = Deploy::GateEnvironment::Gate.new(name: "x", path: "y")
    previous = ENV.delete("DEPLOY_ASSUME_VPS")
    if File.file?("/etc/relayd.conf")
      assert_nil Deploy::GateEnvironment.skip_reason(vps_gate)
    else
      assert_equal "not on VPS", Deploy::GateEnvironment.skip_reason(vps_gate)
    end
    assert_nil Deploy::GateEnvironment.skip_reason(plain)
  ensure
    ENV["DEPLOY_ASSUME_VPS"] = previous if previous
  end

  # A need nothing reads is a claim with no effect; integrity_gate.rb skips on
  # exactly these three.
  def test_integrity_gates_declare_only_needs_skip_reason_reads
    needs = Deploy::GateEnvironment::INTEGRITY_GATES.flat_map(&:needs).uniq
    assert_empty needs - %i[vps bundle browser]
  end

  def test_every_integrity_gate_script_exists
    root = File.expand_path("../..", __dir__)
    missing = Deploy::GateEnvironment::INTEGRITY_GATES.map(&:path).uniq.reject { |path| File.file?(File.join(root, path)) }
    assert_empty missing
  end

  def test_vps_health_gate_targets_core_health_check
    gate = Deploy::GateEnvironment::INTEGRITY_GATES.find { |entry| entry.name == "vps_health" }
    refute_nil gate
    assert_equal "OPENBSD/health_check.rb", gate.path
    assert_equal ["--core"], gate.args
    assert_includes gate.needs, :vps
  end
end
