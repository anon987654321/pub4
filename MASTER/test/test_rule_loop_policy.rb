# frozen_string_literal: true

require_relative "test_helper"

class TestRuleLoopPolicy < Minitest::Test
  Rule = Struct.new(:id, :severity)

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  class Scanner
    def initialize(allow_autofix: true)
      @allow_autofix = allow_autofix
    end

    def scan(_path, rules: nil)
      Master::Result.ok([{ rule: "TEST_RULE", severity: :warning, line: 1, message: "fix me" }])
    end

    def should_autofix?(_rule_id, _confidence)
      @allow_autofix
    end
  end

  class RecordingScanner
    attr_reader :paths

    def initialize
      @paths = []
    end

    def scan(path, rules: nil)
      @paths << path
      source = File.read(path)
      findings = Array.new(source.scan("violation").size) do |index|
        { rule: "TEST_RULE", severity: :warning, line: index + 1, message: "fix me" }
      end
      Master::Result.ok(findings)
    end
  end

  class Agent
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = 0
    end

    def ask(_prompt)
      @calls += 1
      raise @error if @error
      "UNCHANGED"
    end
  end

  def test_prediction_engine_can_skip_autofix
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      agent = Agent.new
      loop = build_loop(root:, bus:, scanner: Scanner.new(allow_autofix: false), agent:)

      result = loop.run_once([path])

      assert_equal 0, result[:fixed]
      assert_equal 0, agent.calls
      assert_includes bus.events.map(&:first), "rule_loop:autofix_skipped"
    end
  end

  # A confidence-gated skip was never actually attempted -- recording it as
  # :stuck (same as a genuine failed fix) would silently poison that rule's
  # fix_quality every time the gate fires, deprioritizing it further with no
  # real defect behind it (the OpenCrabs feedback_policy.rs lesson).
  class RecordingLearnings
    attr_reader :calls

    def initialize
      @calls = []
    end

    def record(**kwargs)
      @calls << kwargs
    end
  end

  def test_confidence_skip_records_skipped_not_stuck
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      learnings = RecordingLearnings.new
      loop = Master::Fix::RuleLoop.new(
        rule: Rule.new("TEST_RULE", :warning),
        agent: Agent.new,
        scanner: Scanner.new(allow_autofix: false),
        root:,
        bus: FakeBus.new,
        learnings:,
      )

      result = loop.run_once([path])

      assert_equal :skipped, result[:status]
      assert_equal [{ rule: "TEST_RULE", file_type: "rb", outcome: :skipped }], learnings.calls
    end
  end

  def test_permanent_failure_uses_fail_fast_branch
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      agent = Agent.new(error: RuntimeError.new("permission denied"))
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent:)

      result = loop.run_once([path])

      assert_equal :stuck, result[:status]
      assert_includes bus.events.map(&:first), "rule_loop:fail_fast"
    end
  end

  def test_ambiguous_failure_requests_human_intervention
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      agent = Agent.new(error: RuntimeError.new("partial write detected"))
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent:)

      result = loop.run_once([path])

      assert_equal :stuck, result[:status]
      assert_includes bus.events.map(&:first), "rule_loop:human_intervention"
    end
  end

  def test_preamble_loads_soul_once_across_rule_loops
    original = Master.method(:load_yaml)
    count = 0
    Master::Fix::RuleLoop.clear_preamble_cache!
    Master.define_singleton_method(:load_yaml) do |path, symbolize_names: false, default: {}|
      if path.end_with?("soul.yml")
        count += 1
        { "absolute" => { "golden_rule" => "CACHE_ME" } }
      else
        original.call(path, symbolize_names:, default:)
      end
    end

    Dir.mktmpdir do |root|
      first = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)
      second = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)
      count = 0

      assert_includes first.__send__(:preamble), "CACHE_ME"
      assert_includes second.__send__(:preamble), "CACHE_ME"
      assert_operator count, :<=, 1, "soul.yml should load at most once per preamble cache"
    end
  ensure
    Master.define_singleton_method(:load_yaml) do |path, symbolize_names: false, default: {}|
      original.call(path, symbolize_names:, default:)
    end
    Master::Fix::RuleLoop.clear_preamble_cache!
  end

  def test_rescan_candidate_preserves_original_file_extension
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      scanner = RecordingScanner.new
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent: Agent.new)

      count = loop.__send__(:rescan_candidate, "clean\n", path)

      assert_equal 0, count
      assert_equal ".rb", File.extname(scanner.paths.last)
    end
  end

  def test_best_candidate_rejects_candidates_that_increase_violations
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      scanner = RecordingScanner.new
      loop = build_loop(root:, bus: FakeBus.new, scanner:, agent: Agent.new)

      best = loop.__send__(:best_candidate, %W[violation\nviolation\n clean\n], path)

      assert_equal "clean\n", best
    end
  end

  # Regression: `return match[1].strip if (match = text.match(...))` raised
  # NameError every time the regex actually matched -- Ruby's parser hadn't
  # seen the `match =` assignment yet at the point `match[1]` is read
  # (textually earlier on the same line), so it tried to call a `match`
  # method instead of using the local var. This meant extract_code crashed
  # on every LLM response containing a real fenced code block -- the normal
  # case -- silently swallowed by the callers' rescue StandardError, so
  # genetic_fix/architect_then_fix degraded to whole_file_fallback (or
  # exhausted retries) even when the LLM behaved correctly.
  def test_extract_code_handles_fenced_response_without_nameerror
    Dir.mktmpdir do |root|
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)

      result = loop.__send__(:extract_code, "here is the fix:\n```ruby\nputs 1\n```\n", ".rb")

      assert_equal "puts 1", result
    end
  end

  def test_extract_code_passes_through_unfenced_response
    Dir.mktmpdir do |root|
      loop = build_loop(root:, bus: FakeBus.new, scanner: Scanner.new, agent: Agent.new)

      result = loop.__send__(:extract_code, "plain response, no code fence")

      assert_equal "plain response, no code fence", result
    end
  end

  private

  class SilentAgent
    def ask(_prompt) = ""
    def ask_once(_prompt, **) = ""
  end

  # The 2026-08-19 proof run reported fixed=0 for 33 minutes and the log could
  # not say why: every non-apply collapsed to false before the one aggregate
  # line. Each outcome is a named symbol now, and a model that returns nothing
  # is :no_proposal — a different problem from a proposal dying in review, and
  # the breakdown line must say which.
  def test_a_model_that_returns_nothing_is_a_named_outcome
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: Scanner.new, agent: SilentAgent.new)

      outcome = loop.send(:fix_violation,
                          Master::Fix::RuleLoop::Violation.from_finding(
                            { rule: "TEST_RULE", severity: :warning, line: 1, message: "fix me" },
                            file: path, ext: ".rb",
                          ))

      assert_equal :no_proposal, outcome
    end
  end

  def build_loop(root:, bus:, scanner:, agent:)
    Master::Fix::RuleLoop.new(
      rule: Rule.new("TEST_RULE", :warning),
      agent:,
      scanner:,
      root:,
      bus:,
    )
  end
end
