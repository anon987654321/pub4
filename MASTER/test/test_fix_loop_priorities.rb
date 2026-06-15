# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestFixLoopPriorities < Minitest::Test
  Rule = Struct.new(:id, :severity)

  class Scanner
    def scan(_path) = Master::Result.ok([])
  end

  class Agent
    def circuit_breaker = nil
  end

  def test_tier2_quality_rules_are_ordered_before_generic_rules
    Dir.mktmpdir do |dir|
      rules = [Rule.new("GENERIC", :warning), Rule.new("KISS", :warning), Rule.new("DRY", :warning), Rule.new("SRP", :warning)]
      loop = Master::Loop::FixLoop.new(rules:, agent: Agent.new, scanner: Scanner.new, root: dir)

      ordered = loop.__send__(:ordered_rules).map(&:id)

      assert_equal %w[KISS DRY SRP], ordered.first(3)
      assert_equal "GENERIC", ordered.last
    end
  end

  def test_age_and_severity_can_outrank_fresh_low_severity_findings
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "violation_age.yml"), { "OLD_ERROR" => 60, "NEW_WARNING" => 0 }.to_yaml)
      rules = [Rule.new("NEW_WARNING", :warning), Rule.new("OLD_ERROR", :error)]
      order = Master::Loop::FixLoop::RuleOrder.new(rules:, learnings: nil, bus: nil, root: dir)

      ordered = order.ordered(violation_counts: { "NEW_WARNING" => 3, "OLD_ERROR" => 2 }).map(&:id)

      assert_equal "OLD_ERROR", ordered.first
    end
  end
end
