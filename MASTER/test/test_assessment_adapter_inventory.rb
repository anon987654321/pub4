# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop/pass_runner/assessment_matrix"

class TestAssessmentAdapterInventory < Minitest::Test
  include Master::Fix::FixLoop::PassRunner::AssessmentMatrix

  class Applicable
    def initialize(value) = @value = value
    def applicable?(_target) = @value
  end

  def runner(visual:, opportunities:)
    instance = Object.new
    instance.extend(Master::Fix::FixLoop::PassRunner::AssessmentMatrix)
    instance.instance_variable_set(:@visual_pass, visual)
    instance.instance_variable_set(:@opportunity_pass, opportunities)
    instance.instance_variable_set(:@scan_phase, nil)
    instance.instance_variable_set(:@scanner, Object.new)
    instance.instance_variable_set(:@reference_graph, nil)
    instance.instance_variable_set(:@council, nil)
    instance
  end

  def test_missing_visual_or_opportunity_adapters_are_unavailable_not_not_applicable
    adapters = runner(visual: nil, opportunities: nil).assessment_adapters(target: "RAILS")

    assert_equal "unavailable", adapters.fetch("rendered_ui")
    assert_equal "unavailable", adapters.fetch("interactive_behavior")
    assert_equal "unavailable", adapters.fetch("lexical_opportunities")
  end

  def test_present_but_non_applicable_adapters_are_distinguished_from_missing
    adapters = runner(
      visual: Applicable.new(false),
      opportunities: Applicable.new(false)
    ).assessment_adapters(target: "MASTER")

    assert_equal "not_applicable_to_target", adapters.fetch("rendered_ui")
    assert_equal "not_applicable_to_target", adapters.fetch("interactive_behavior")
    assert_equal "not_applicable_to_target", adapters.fetch("lexical_opportunities")
  end

  def test_applicable_visual_adapter_advertises_both_render_and_interaction_probes
    adapters = runner(
      visual: Applicable.new(true),
      opportunities: Applicable.new(true)
    ).assessment_adapters(target: "RAILS")

    assert_equal "visual_pass", adapters.fetch("rendered_ui")
    assert_equal "browser_journeys", adapters.fetch("interactive_behavior")
    assert_equal "opportunity_pass", adapters.fetch("lexical_opportunities")
  end
end
