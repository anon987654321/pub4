# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../lib/gate_result"
require_relative "../lib/gate_environment"
require_relative "../gates/integrity_gate"

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

    assert_equal "not on VPS", Deploy::GateEnvironment.skip_reason(vps_gate, on_vps: false)
    assert_nil Deploy::GateEnvironment.skip_reason(vps_gate, on_vps: true)
    assert_nil Deploy::GateEnvironment.skip_reason(plain, on_vps: false)
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
    assert_equal "OPENBSD/gates/health_check.rb", gate.path
    assert_equal ["--core"], gate.args
    assert_includes gate.needs, :vps
  end
end

# integrity_gate.rb's loop, handed fake gates and a recording executor so the
# verdicts are its own and no real gate runs.
class IntegrityRunTest < Minitest::Test
  Gate = Deploy::GateEnvironment::Gate

  def setup
    @root = Dir.mktmpdir("integrity")
    %w[pass.rb fail.rb soft.rb box.rb].each { |name| File.write(File.join(@root, name), "") }
    @ran = []
  end

  def teardown = FileUtils.rm_rf(@root)

  def run_chain(gates, on_vps:)
    execute = lambda do |cmd|
      script = File.basename(cmd[1])
      @ran << script
      [script == "pass.rb" ? "" : "boom\n", script == "pass.rb"]
    end
    integrity_run(gates, root: @root, on_vps:, execute:, io: StringIO.new)
  end

  def test_a_vps_gate_off_the_box_is_skipped_and_never_executed
    report = run_chain([Gate.new(name: "vps_health", path: "box.rb", needs: %i[vps])], on_vps: false)

    assert_equal ["vps_health: not on VPS"], report[:skipped]
    assert_empty @ran
    assert_empty report[:failures]
  end

  def test_a_vps_gate_on_the_box_runs_and_its_failure_blocks
    report = nil
    _, err = capture_io { report = run_chain([Gate.new(name: "vps_health", path: "box.rb", needs: %i[vps])], on_vps: true) }

    assert_equal ["box.rb"], @ran
    assert_equal ["vps_health"], report[:failures]
    assert_empty err, "the post-pull note is for a connect failure, not every failure"
  end

  def test_required_failures_block_and_optional_ones_warn
    gates = [
      Gate.new(name: "good", path: "pass.rb"),
      Gate.new(name: "bad", path: "fail.rb"),
      Gate.new(name: "soft", path: "soft.rb", optional: true),
    ]
    report = run_chain(gates, on_vps: false)

    assert_equal %w[pass.rb fail.rb soft.rb], @ran
    assert_equal ["bad"], report[:failures]
    assert_equal ["soft: boom"], report[:warnings]
  end

  # crawl_probe exits 3 when no app is listening. That is neither a pass nor a
  # failure, so the chain lists it as skipped unless strict mode asks it to block.
  def test_a_gate_that_measured_nothing_is_skipped_unless_strict
    gates = [Gate.new(name: "crawl", path: "pass.rb")]
    execute = ->(_cmd) { ["crawl: inconclusive (4 targets, 4 skipped)\n", :inconclusive] }

    report = integrity_run(gates, root: @root, on_vps: false, execute:, io: StringIO.new)
    assert_empty report[:failures]
    assert_equal ["crawl: measured nothing — crawl: inconclusive (4 targets, 4 skipped)"], report[:skipped]

    ENV["GATE_STRICT_INCONCLUSIVE"] = "1"
    strict = integrity_run(gates, root: @root, on_vps: false, execute:, io: StringIO.new)
    assert_equal ["crawl"], strict[:failures]
  ensure
    ENV.delete("GATE_STRICT_INCONCLUSIVE")
  end

  def test_a_gate_whose_script_is_gone_is_a_warning_not_a_pass
    report = run_chain([Gate.new(name: "ghost", path: "nowhere.rb")], on_vps: true)

    assert_equal ["ghost: missing nowhere.rb"], report[:warnings]
    assert_empty @ran
  end
end
