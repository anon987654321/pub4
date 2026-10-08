# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestFixLoopPriorities < Minitest::Test
  Law = Struct.new(:id, :severity)

  class Scanner
    def scan(_path) = Master::Result.ok([])
  end

  class Agent
    def circuit_breaker = nil
  end

  def test_tier2_quality_laws_are_ordered_before_generic_laws
    Dir.mktmpdir do |dir|
      ids = Master::Fix::FixLoop::LawOrder::TIER2_QUALITY_LAW_IDS
      laws = [Law.new("GENERIC", :warning), *ids.map { |id| Rule.new(id, :warning) }]
      loop = Master::Fix::FixLoop.new(rules:, agent: Agent.new, scanner: Scanner.new, root: dir)

      ordered = loop.__send__(:ordered_rules).map(&:id)

      assert_equal ids.size, (ordered.first(ids.size) & ids).size
      assert_equal "GENERIC", ordered.last
    end
  end

  def test_tier2_ids_exist_on_the_live_scanner
    require "fix/scanner"
    scanner = Master::Fix::Scanner.build(root: Master::ROOT)
    ids = scanner.laws.map { |rule| rule.id.to_s }
    missing = Master::Fix::FixLoop::LawOrder::TIER2_QUALITY_RULE_IDS - ids

    assert_empty missing, "tier2 names laws the scanner does not build: #{missing.join(", ")}"
  end

  def test_absent_violation_priors_do_not_break_law_ordering
    Dir.mktmpdir do |dir|
      rules = [Rule.new("A", :warning), Rule.new("B", :error)]
      order = Master::Fix::FixLoop::LawOrder.new(laws:, learnings: nil, bus: nil, root: dir)

      assert_equal %w[B A], order.ordered(violation_counts: {}).map(&:id)
    end
  end

  def test_age_and_severity_can_outrank_fresh_low_severity_laws
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "violation_age.yml"), { "OLD_ERROR" => 60, "NEW_WARNING" => 0 }.to_yaml)
      rules = [Rule.new("NEW_WARNING", :warning), Rule.new("OLD_ERROR", :error)]
      order = Master::Fix::FixLoop::LawOrder.new(rules:, learnings: nil, bus: nil, root: dir)

      ordered = order.ordered(violation_counts: { "NEW_WARNING" => 3, "OLD_ERROR" => 2 }).map(&:id)

      assert_equal "OLD_ERROR", ordered.first
    end
  end
end
