# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "cli/pipeline/proof"

class TestProofAffected < Minitest::Test
  Affected = Master::CLI::Pipeline::Proof::Affected
  Reading = Master::CLI::Pipeline::Proof::Reading
  SUMMARY = "3 runs, 3 assertions, 1 failures, 0 errors, 0 skips"
  OLD = ["  1) Failure:", "TestX#test_old [test/x.rb:1]:"].freeze
  NONE = Affected::Known.new(failing: Set.new, rows: {})

  def reading(*lines, ok: false) = Reading.parse(ok, ["proof suite MASTER affected (1 files): FAIL", *lines])

  def test_a_test_file_proves_itself_and_a_lib_file_its_naming_tests
    assert_equal ["test/test_finding_cache.rb"], Affected.tests_for(["test/test_finding_cache.rb"])
    assert_includes Affected.tests_for(["lib/fix/scan/finding_cache.rb"]), "test/test_finding_cache.rb"
  end

  # The code every test boots through, and a change no test names, take the whole suite.
  def test_wide_or_unnamed_changes_take_the_whole_suite
    assert_nil Affected.tests_for(["lib/master.rb"])
    assert_nil Affected.tests_for(["test/test_helper.rb", "test/test_finding_cache.rb"])
    assert_nil Affected.tests_for(["data/laws.yml"])
    assert_nil Affected.tests_for(["README.md"])
    assert_nil Affected.tests_for([])
  end

  def test_a_failure_already_red_holds_and_a_new_one_does_not
    red = reading(*OLD, SUMMARY)

    assert Affected.judge(red, NONE.with(failing: Set["TestX#test_old"])).first
    held, verdict = Affected.judge(red, NONE)
    refute held
    assert_match(/TestX#test_old/, verdict)
  end

  def test_a_run_that_never_reached_its_summary_does_not_hold
    refute Affected.judge(reading("LoadError: cannot load such file"), NONE).first
  end

  def test_a_ratchet_row_above_the_record_does_not_hold
    rows = reading("  [DENSITY] 7", SUMMARY, ok: true)

    assert Affected.judge(rows, NONE.with(rows: { "selftest DENSITY" => 7 })).first
    refute Affected.judge(rows, NONE.with(rows: { "selftest DENSITY" => 6 })).first
  end

  def test_the_record_round_trips_and_honours_the_store_switch
    Dir.mktmpdir do |dir|
      ENV["MASTER_PROOF_KNOWN_RED_DIR"] = dir
      ENV["MASTER_PROOF_STORE"] = "1"
      Affected.note_known_red("MASTER", reading(*OLD, SUMMARY))

      assert_equal Set["TestX#test_old"], Affected.known_red("MASTER").failing
      ENV["MASTER_PROOF_STORE"] = "0"
      assert_nil Affected.known_red("MASTER")
    ensure
      ENV.delete("MASTER_PROOF_KNOWN_RED_DIR")
      ENV["MASTER_PROOF_STORE"] = "0"
    end
  end

  # A record from another toolchain, or past its age, no longer says what is red.
  def test_a_stale_record_proves_whole
    refute_nil known_after({})
    assert_nil known_after("toolchain" => "3.3.0 0000")
    assert_nil known_after({}, omit: ["toolchain"])
    assert_nil known_after("failing" => "not-an-array")
    assert_nil known_after("rows" => ["not-a-map"])
    assert_nil known_after("at" => (Time.now.utc + 3600).iso8601)
    assert_nil known_after("at" => (Time.now.utc - Affected::MAX_AGE_S - 60).iso8601)
  end

  def known_after(change, omit: [])
    Dir.mktmpdir do |dir|
      ENV["MASTER_PROOF_KNOWN_RED_DIR"] = dir
      ENV["MASTER_PROOF_STORE"] = "1"
      record = { "failing" => [], "rows" => {}, "at" => Time.now.utc.iso8601, "toolchain" => Affected.toolchain }
      File.write(File.join(dir, "MASTER.json"), JSON.generate(record.merge(change).reject { |key, _| omit.include?(key) }))

      Affected.known_red("MASTER")
    ensure
      ENV.delete("MASTER_PROOF_KNOWN_RED_DIR")
      ENV["MASTER_PROOF_STORE"] = "0"
    end
  end
end

# The pass end of it: which proof runs, and what it is judged by.
class TestProofAffectedPass < Minitest::Test
  OLD = ["  1) Failure:", "TestX#test_old [test/x.rb:1]:"].freeze
  NEW = ["  1) Failure:", "TestX#test_new [test/x.rb:1]:"].freeze
  SUMMARY = "3 runs, 3 assertions, 1 failures, 0 errors, 0 skips"

  class NarrowPass < Master::CLI::Pipeline::Pass
    attr_reader :full_runs, :narrow_runs, :delivered, :failed_stages

    def initialize(repair_paths, out)
      @failed_stages = []
      @causes = {}
      @paths = repair_paths
      @out = [false, ["proof suite MASTER: FAIL", *out]]
      @full_runs = @narrow_runs = 0
      @delivered = []
    end

    def proof_runner(_abs) = ["MASTER", -> { (@full_runs += 1) && @out }]
    def affected_runner(_tests) = ["affected", -> { (@narrow_runs += 1) && @out }]
    def deliver_leftovers(_abs, verdict) = (@delivered << verdict) && "delivery: stubbed"
    def repair_paths = @paths
    def prove(baseline = nil) = proof_section(Master::ROOT, baseline)
  end

  def setup
    @dir = Dir.mktmpdir
    @saved = %w[MASTER_IN_PROOF MASTER_PROOF_STORE MASTER_PROOF_KNOWN_RED_DIR].to_h { |key| [key, ENV.delete(key)] }
    ENV["MASTER_PROOF_KNOWN_RED_DIR"] = @dir
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    FileUtils.remove_entry(@dir)
  end

  def record_old_red
    reading = Master::CLI::Pipeline::Proof::Reading.parse(false, ["proof suite MASTER: FAIL", *OLD, SUMMARY])
    Master::CLI::Pipeline::Proof::Affected.note_known_red("MASTER", reading)
  end

  def test_a_named_change_runs_only_its_tests_and_holds_on_an_old_failure
    record_old_red
    pass = NarrowPass.new(["test/test_finding_cache.rb"], [*OLD, SUMMARY])
    pass.prove

    assert_equal [1, 0], [pass.narrow_runs, pass.full_runs]
    assert_empty pass.failed_stages
    assert_equal 1, pass.delivered.size
  end

  def test_a_new_failure_in_the_affected_tests_refuses
    record_old_red
    pass = NarrowPass.new(["test/test_finding_cache.rb"], [*NEW, SUMMARY])
    pass.prove

    assert_equal ["proof"], pass.failed_stages
    assert_empty pass.delivered
  end

  def test_a_wide_change_runs_the_whole_suite_against_the_record
    record_old_red
    pass = NarrowPass.new(["lib/master.rb"], [*OLD, SUMMARY])
    pass.prove

    assert_equal [0, 1], [pass.narrow_runs, pass.full_runs]
    assert_empty pass.failed_stages
  end

  # Before any whole suite has run there is nothing to judge a narrow proof by.
  def test_without_a_record_or_baseline_the_whole_suite_must_be_green
    pass = NarrowPass.new(["test/test_finding_cache.rb"], [*OLD, SUMMARY])
    pass.prove

    assert_equal [0, 1], [pass.narrow_runs, pass.full_runs]
    assert_equal ["proof"], pass.failed_stages
  end
end
