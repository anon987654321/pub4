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
    Master::Loop::RuleLoop.clear_preamble_cache!
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

      assert_includes first.__send__(:preamble), "CACHE_ME"
      assert_includes second.__send__(:preamble), "CACHE_ME"
      assert_equal 1, count
    end
  ensure
    Master.define_singleton_method(:load_yaml) do |path, symbolize_names: false, default: {}|
      original.call(path, symbolize_names:, default:)
    end
    Master::Loop::RuleLoop.clear_preamble_cache!
  end

  private

  def build_loop(root:, bus:, scanner:, agent:)
    Master::Loop::RuleLoop.new(
      rule: Rule.new("TEST_RULE", :warning),
      agent:,
      scanner:,
      root:,
      bus:
    )
  end
end
