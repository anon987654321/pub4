# frozen_string_literal: true

require_relative "test_helper"

class TestFixLoopPriorities < Minitest::Test
  Rule = Struct.new(:id)

  class Scanner
    def scan(_path) = Master::Result.ok([])
  end

  class Agent
    def circuit_breaker = nil
  end

  def test_tier2_quality_rules_are_ordered_before_generic_rules
    Dir.mktmpdir do |dir|
      rules = [Rule.new("GENERIC"), Rule.new("KISS"), Rule.new("DRY"), Rule.new("SRP")]
      loop = Master::Loop::FixLoop.new(rules:, agent: Agent.new, scanner: Scanner.new, root: dir)

      ordered = loop.__send__(:ordered_rules).map(&:id)

      assert_equal %w[KISS DRY SRP], ordered.first(3)
      assert_equal "GENERIC", ordered.last
    end
  end
end
