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
      laws = [Law.new("GENERIC", :warning), *ids.map { |id| Law.new(id, :warning) }]
      loop = Master::Fix::FixLoop.new(laws:, agent: Agent.new, scanner: Scanner.new, root: dir)

      order = loop.instance_variable_get(:@pass_runner).instance_variable_get(:@law_order)
      ordered = order.ordered(violation_counts: {}).map(&:id)

      assert_equal ids.size, (ordered.first(ids.size) & ids).size
      assert_equal "GENERIC", ordered.last
    end
  end

  def test_tier2_ids_exist_on_the_live_scanner
    require "fix/scanner"
    scanner = Master::Fix::Scanner.build(root: Master::ROOT)
    ids = scanner.laws.map { |law| law.id.to_s }
    missing = Master::Fix::FixLoop::LawOrder::TIER2_QUALITY_LAW_IDS - ids

    assert_empty missing, "tier2 names laws the scanner does not build: #{missing.join(", ")}"
  end

  def test_absent_violation_priors_do_not_break_law_ordering
    Dir.mktmpdir do |dir|
      laws = [Law.new("A", :warning), Law.new("B", :error)]
      order = Master::Fix::FixLoop::LawOrder.new(laws:, learnings: nil, bus: nil, root: dir)

      assert_equal %w[B A], order.ordered(violation_counts: {}).map(&:id)
    end
  end

  def test_age_and_severity_can_outrank_fresh_low_severity_laws
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "violation_age.yml"), { "OLD_ERROR" => 60, "NEW_WARNING" => 0 }.to_yaml)
      laws = [Law.new("NEW_WARNING", :warning), Law.new("OLD_ERROR", :error)]
      order = Master::Fix::FixLoop::LawOrder.new(laws:, learnings: nil, bus: nil, root: dir)

      ordered = order.ordered(violation_counts: { "NEW_WARNING" => 3, "OLD_ERROR" => 2 }).map(&:id)

      assert_equal "OLD_ERROR", ordered.first
    end
  end

  # A broken page outranks a rendered defect, and a rendered defect outranks a code law.
  def test_findings_users_meet_are_ranked_first
    order = Master::Fix::FixLoop::LawOrder
    tier = ->(finding) { order::IMPACT_TIERS.fetch(order.impact(finding)) }

    assert_equal :runtime, tier.({ law: "RUBOCOP", message: "uncaught JavaScript exception: TypeError" })
    assert_equal :runtime, tier.({ message: "document returned HTTP 404" })
    assert_equal :runtime, tier.({ message: "first-party resource failed: HTTP 500 /assets/app.css (Stylesheet)" })
    assert_equal :runtime, tier.({ "message" => "browser console error: network: Failed to load resource" })
    assert_equal :rendered, tier.({ law: "RENDERED_VISUAL_REFINEMENT", message: "card padding drifts" })
    assert_equal :rendered, tier.({ law: "SCALE_SNAP", message: "off-scale space" })
    assert_equal :code, tier.({ law: "FEATURE_ENVY", message: "method reaches into another object" })
  end

  def test_a_file_ranks_by_its_most_urgent_finding
    order = Master::Fix::FixLoop::LawOrder
    rows = [{ law: "FEATURE_ENVY", message: "x" }, { law: "X", message: "document returned HTTP 500" }]

    assert_equal 0, order.file_impact(rows)
    assert_equal 2, order.file_impact([{ law: "FEATURE_ENVY" }])
  end

  def test_rendered_laws_precede_tier2_and_generic_code_laws
    Dir.mktmpdir do |dir|
      laws = [Law.new("GENERIC", :error), Law.new("FEATURE_ENVY", :warning),
              Law.new("RENDERED_VISUAL_REFINEMENT", :warning)]
      order = Master::Fix::FixLoop::LawOrder.new(laws:, learnings: nil, bus: nil, root: dir)

      assert_equal %w[RENDERED_VISUAL_REFINEMENT FEATURE_ENVY GENERIC], order.ordered(violation_counts: {}).map(&:id)
    end
  end
end
