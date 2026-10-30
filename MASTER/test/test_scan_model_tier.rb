# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../lib/review/scan/law_tree"

# A tree-wide scan walks thousands of files. The model tier was reached from the
# lexical pass (AdversarialLaw, CommentDriftLaw) and from every file with a
# finding, which on RAILS is three files in four: about 5,000 model calls of a
# minute each inside one walk, an estimated 62 hours for a scan that measures
# 75 seconds without them.
class ScanModelTierTest < Minitest::Test
  class ModelLaw
    attr_reader :calls

    def initialize = @calls = 0
    def id = "model_stub"
    def set_agent(_agent) = self
    def check(_code, path:) = (@calls += 1; [])
  end

  class CheapLaw
    def initialize(findings) = @findings = findings
    def id = "cheap_stub"
    def check(_code, path:) = @findings
  end

  FINDING = { law: "CHEAP", severity: :warning, line: 1, message: "m" }.freeze

  def setup
    @dir = Dir.mktmpdir("model-tier")
    @path = File.join(@dir, "note.md")
    File.write(@path, "# Note\n")
  end

  def teardown = FileUtils.rm_rf(@dir)

  def scanner(model, findings: [])
    Master::Fix::Scanner.new(laws: [CheapLaw.new(findings), model])
  end

  # With the daily sample off. The sample picks files by a hash of their path, and this file sits in a
  # random temp directory, so leaving the posture's rate in place made the test fail about one run in ten.
  def test_a_model_law_never_runs_in_the_lexical_pass_of_a_clean_file
    model = ModelLaw.new
    Master::Ground::ModePosture.stub(:semantic_sample, 0.0) { assert scanner(model).scan(@path).ok? }
    assert_equal 0, model.calls
  end

  def test_a_file_with_a_finding_still_reaches_the_model_tier_in_a_writing_run
    model = ModelLaw.new
    scanner(model, findings: [FINDING]).scan(@path)
    assert_equal 1, model.calls
  end

  def test_a_mechanical_reading_skips_the_model_tier_and_restores_it
    model = ModelLaw.new
    sc = scanner(model, findings: [FINDING])
    sc.mechanical_only { assert_equal 1, sc.scan(@path).value!.size }
    assert_equal 0, model.calls
    sc.scan(@path)
    assert_equal 1, model.calls
  end

  def test_the_operator_asking_for_every_file_wins_over_a_mechanical_reading
    model = ModelLaw.new
    sc = scanner(model)

    with_env("MASTER_SCAN_SEMANTIC_SAMPLE" => "1") do
      sc.full_semantic!
      sc.mechanical_only { sc.scan(@path) }
    end
    assert_equal 1, model.calls
  end

  # A requested /fix sets full coverage on the scanner it shares with the
  # pipeline; the re-observe after it must still be a mechanical reading.
  def test_a_repairs_full_coverage_does_not_reach_the_observation
    model = ModelLaw.new
    sc = scanner(model, findings: [FINDING])

    with_env("MASTER_SCAN_SEMANTIC_SAMPLE" => "0.1") do
      sc.full_semantic!
      sc.mechanical_only { sc.scan(@path) }
    end
    assert_equal 0, model.calls
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  # Scan-only callers build the scanner with no agent. The model laws are then
  # not asked at all: no swallow row per file, one tier-level note per run, and
  # each file keeps a gap so the reading is inconclusive rather than clean.

  def agentless_scanner
    laws = Master::Review::Scan::Laws
    model_laws = [laws::SemanticLaw, laws::AdversarialLaw, laws::CommentDriftLaw].map { |klass| klass.new(agent: nil) }
    Master::Fix::Scanner.new(laws: [CheapLaw.new([FINDING]), *model_laws])
  end

  # Every Swallow row and every dmesg line the block writes.
  def recording(swallowed, notes, &)
    Master::Ground::Swallow.stub(:log, ->(*args, **kwargs) { swallowed << [args, kwargs] }) do
      Master::Trace::Dmesg.stub(:status, ->(unit, msg, **) { notes << "#{unit} #{msg}" }, &)
    end
  end

  def test_a_scan_with_no_agent_is_inconclusive_once_and_logs_nothing
    other = File.join(@dir, "other.rb")
    File.write(other, "x = 1\n")
    sc = agentless_scanner
    swallowed = []
    notes = []

    recording(swallowed, notes) { [@path, other].each { |path| assert sc.scan(path).ok? } }

    assert_empty swallowed, "an agentless scan wrote swallow rows"
    assert_equal 1, notes.grep(/semantic tier inconclusive/).size, notes.inspect
    assert_equal 2, sc.semantic_gaps.values.grep(/INCONCLUSIVE/).size, "each unasked file must stay inconclusive"
  end

  def test_a_model_law_with_an_agent_still_runs
    asked = []
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt, operation:| (asked << operation; "CLEAN") }
    sc = Master::Fix::Scanner.new(laws: [CheapLaw.new([FINDING]),
                                         Master::Review::Scan::Laws::AdversarialLaw.new(agent:)])

    assert sc.scan(@path).ok?
    assert_equal [:scan_adversarial], asked
    assert_empty sc.semantic_gaps
  end

  # The budget: the real law set over a real prose file, behind an agent that
  # would take half a second a call. Under the old routing this took two calls.
  def test_the_real_law_set_scans_a_prose_file_inside_the_budget
    slow = Class.new do
      attr_reader :asked

      def ask(*, **) = (@asked = @asked.to_i + 1; sleep 0.5; "CLEAN")
    end.new
    sc = Master::Fix::Scanner.build(root: Master::ROOT, agent: slow)
    sc.set_agent(slow)
    File.write(@path, "# Note\n\n#{"A line of prose that runs on and on. " * 40}\n\n\n\nEnd\n")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sc.mechanical_only { assert sc.scan(@path).ok? }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil slow.asked
    assert_operator elapsed, :<, 2.0
  end
end
