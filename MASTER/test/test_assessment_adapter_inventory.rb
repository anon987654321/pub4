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
  ScannerOnlyOpportunity = Struct.new(:id, :mode)

  def test_scanner_only_law_mode_does_not_abort_matrix_initialization
    scanner_law = ScannerOnlyOpportunity.new("ASSESSMENT_MATRIX_SCANNER_ONLY", :opportunity)
    scanner = Object.new
    scanner.define_singleton_method(:laws) { [scanner_law] }

    plan = Struct.new(:target, :digest, :root, :sources, :source_signatures).new(
      Master::ROOT, "plan-digest", Master::ROOT, [], {}
    )
    subject = Object.new.extend(Master::Fix::FixLoop::PassRunner::AssessmentMatrix)
    subject.instance_variable_set(:@scanner, scanner)
    subject.instance_variable_set(:@assessment_mutex, Mutex.new)
    subject.instance_variable_set(:@clean_runs_required, 2)
    subject.instance_variable_set(:@visual_pass, nil)
    subject.instance_variable_set(:@opportunity_pass, nil)
    subject.define_singleton_method(:stage_failures) do
      @stage_failures ||= Hash.new { |hash, key| hash[key] = [] }
    end

    subject.begin_assessment_run(files: [], plan:)

    refute_nil subject.instance_variable_get(:@assessment_ledger),
      "one scanner-only Law must not collapse the entire proof matrix to not_measured"
    assert_empty subject.stage_failures[:assessment_matrix]
    assert_equal [:lexical_violations],
      subject.instance_variable_get(:@assessment_law_info)
        .fetch("ASSESSMENT_MATRIX_SCANNER_ONLY").fetch(:unmeasurable_streams)
  end

end
