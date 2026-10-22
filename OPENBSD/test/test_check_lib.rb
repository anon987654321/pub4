# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../lib/check_result"
require_relative "../lib/check_environment"
require_relative "../checks/integrity_check"

class CheckLibTest < Minitest::Test
  def test_check_result_tracks_failures_and_warnings
    result = Deploy::CheckResult.new
    assert result.ok?

    result.warn("heads up")
    assert result.ok?

    result.fail("blocked")
    refute result.ok?
    assert_equal ["blocked"], result.failures
    assert_equal ["heads up"], result.warnings
  end

  def test_check_result_report_exits_on_failure
    result = Deploy::CheckResult.new
    result.fail("nope")

    assert_raises(SystemExit) { result.report!("should not print") }
  end

  def test_integrity_checks_include_expected_entries
    names = Deploy::CheckEnvironment::INTEGRITY_CHECKS.map(&:name)

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
      assert_includes names, expected, "missing check #{expected}"
    end
  end

  # measured_nothing? separates "declined to measure" from "measured and passed".
  # A result that recorded nothing at all is a pass: it made no claim either way.
  def test_measured_nothing_distinguishes_a_skip_from_a_check
    assert_equal :passed, Deploy::CheckResult.new.outcome

    skipped = Deploy::CheckResult.new.inconclusive!("no Chrome")
    assert skipped.measured_nothing?
    assert_equal :inconclusive, skipped.outcome

    partial = Deploy::CheckResult.new.inconclusive!("no Chrome").checked!(3)
    refute partial.measured_nothing?, "a check that ran three checks measured something"
    assert_equal :passed, partial.outcome

    live = Deploy::CheckResult.new.skipped_live("port 61352 closed")
    assert live.measured_nothing?, "every live check skipped is nothing measured"
  end

  def test_skip_reason_consults_the_needs_it_declares
    vps_check = Deploy::CheckEnvironment::Check.new(name: "x", path: "y", needs: %i[vps])
    plain = Deploy::CheckEnvironment::Check.new(name: "x", path: "y")

    assert_equal "not on VPS", Deploy::CheckEnvironment.skip_reason(vps_check, on_vps: false)
    assert_nil Deploy::CheckEnvironment.skip_reason(vps_check, on_vps: true)
    assert_nil Deploy::CheckEnvironment.skip_reason(plain, on_vps: false)
  end

  # A need nothing reads is a claim with no effect; integrity_check.rb skips on
  # exactly these three.
  def test_integrity_checks_declare_only_needs_skip_reason_reads
    needs = Deploy::CheckEnvironment::INTEGRITY_CHECKS.flat_map(&:needs).uniq
    assert_empty needs - %i[vps bundle browser]
  end

  def test_every_integrity_check_script_exists
    root = File.expand_path("../..", __dir__)
    missing = Deploy::CheckEnvironment::INTEGRITY_CHECKS.map(&:path).uniq.reject { |path| File.file?(File.join(root, path)) }
    assert_empty missing
  end

  def test_vps_health_check_targets_core_health_check
    check = Deploy::CheckEnvironment::INTEGRITY_CHECKS.find { |entry| entry.name == "vps_health" }
    refute_nil check
    assert_equal "OPENBSD/checks/health_check.rb", check.path
    assert_equal ["--core"], check.args
    assert_includes check.needs, :vps
  end
end

# integrity_check.rb's loop, handed fake checks and a recording executor so the
# verdicts are its own and no real check runs.
class IntegrityRunTest < Minitest::Test
  Check = Deploy::CheckEnvironment::Check

  def setup
    @root = Dir.mktmpdir("integrity")
    %w[pass.rb fail.rb soft.rb box.rb].each { |name| File.write(File.join(@root, name), "") }
    @ran = []
  end

  def teardown = FileUtils.rm_rf(@root)

  def run_chain(checks, on_vps:)
    execute = lambda do |cmd|
      script = File.basename(cmd[1])
      @ran << script
      [script == "pass.rb" ? "" : "boom\n", script == "pass.rb"]
    end
    integrity_run(checks, root: @root, on_vps:, execute:, io: StringIO.new)
  end

  def test_a_vps_check_off_the_box_is_skipped_and_never_executed
    report = run_chain([Check.new(name: "vps_health", path: "box.rb", needs: %i[vps])], on_vps: false)

    assert_equal ["vps_health: not on VPS"], report[:skipped]
    assert_empty @ran
    assert_empty report[:failures]
  end

  def test_a_vps_check_on_the_box_runs_and_its_failure_blocks
    report = nil
    _, err = capture_io { report = run_chain([Check.new(name: "vps_health", path: "box.rb", needs: %i[vps])], on_vps: true) }

    assert_equal ["box.rb"], @ran
    assert_equal ["vps_health"], report[:failures]
    assert_empty err, "the post-pull note is for a connect failure, not every failure"
  end

  def test_required_failures_block_and_optional_ones_warn
    checks = [
      Check.new(name: "good", path: "pass.rb"),
      Check.new(name: "bad", path: "fail.rb"),
      Check.new(name: "soft", path: "soft.rb", optional: true),
    ]
    report = run_chain(checks, on_vps: false)

    assert_equal %w[pass.rb fail.rb soft.rb], @ran
    assert_equal ["bad"], report[:failures]
    assert_equal ["soft: boom"], report[:warnings]
  end

  # crawl_probe exits 3 when no app is listening. That is neither a pass nor a
  # failure, so the chain lists it as skipped unless strict mode asks it to block.
  def test_a_check_that_measured_nothing_is_skipped_unless_strict
    previous = ENV["CHECK_STRICT_INCONCLUSIVE"]
    ENV.delete("CHECK_STRICT_INCONCLUSIVE")
    checks = [Check.new(name: "crawl", path: "pass.rb")]
    execute = ->(_cmd) { ["crawl: inconclusive (4 targets, 4 skipped)\n", :inconclusive] }

    report = integrity_run(checks, root: @root, on_vps: false, execute:, io: StringIO.new)
    assert_empty report[:failures]
    assert_equal ["crawl: measured nothing — crawl: inconclusive (4 targets, 4 skipped)"], report[:skipped]

    ENV["CHECK_STRICT_INCONCLUSIVE"] = "1"
    strict = integrity_run(checks, root: @root, on_vps: false, execute:, io: StringIO.new)
    assert_equal ["crawl"], strict[:failures]
  ensure
    previous.nil? ? ENV.delete("CHECK_STRICT_INCONCLUSIVE") : ENV["CHECK_STRICT_INCONCLUSIVE"] = previous
  end

  def test_a_check_whose_script_is_gone_is_a_warning_not_a_pass
    report = run_chain([Check.new(name: "ghost", path: "nowhere.rb")], on_vps: true)

    assert_equal ["ghost: missing nowhere.rb"], report[:warnings]
    assert_empty @ran
  end
end
