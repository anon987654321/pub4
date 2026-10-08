# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/transformation_plan"

class TestTransformationPlan < Minitest::Test
  def setup
    @plan = Master::Fix::TransformationPlan.new(root: Master::ROOT)
  end

  def test_pipeline_has_inventory_and_classification_before_transformations
    assert_equal %w[inventory classify], @plan.preflight
    assert_equal ["prove"], @plan.postflight
    assert_equal %w[
      defragment decouple flatten merge split relocate rename reorder remove
      reflow simplify recommend
    ], @plan.operations.map(&:name)
  end

  def test_structural_order_is_monotonic
    assert @plan.ordered?(%w[defragment flatten merge split relocate rename reorder reflow])
    refute @plan.ordered?(%w[rename merge])
  end

  def test_every_operation_has_a_present_principle
    @plan.operations.each do |operation|
      refute_empty operation.purpose
    end
  end

  def test_preservation_and_evidence_contracts_are_explicit
    preservation = @plan.preservation_contract
    evidence = @plan.evidence_contract

    %w[semantic_meaning public_contracts reference_graph side_effect_order].each do |key|
      assert preservation.key?(key), "missing preservation contract #{key}"
    end
    assert_equal "Record hashes and measured facts from the observed state before mutation.", evidence.fetch("before")
    assert_equal "Re-observe the changed artifact and compare the same facts after mutation.", evidence.fetch("after")
    assert_equal true, evidence.fetch("no_content_copy")
  end

  def test_research_backed_cleanup_profile_is_complete
    ids = @plan.evidence_hierarchy.map { |entry| entry.fetch("id") }
    assert_equal %w[characterization structural runtime history visual semantic taste], ids
    %w[code ruby rails prose visual].each do |domain|
      refute_empty @plan.smell_catalog.fetch(domain)
    end
    %w[ruby rails prose visual].each do |domain|
      refute_empty @plan.domain_adapters.fetch(domain)
    end
    assert_operator @plan.automatic_vetoes.length, :>=, 5
    names = @plan.research.map { |entry| entry.fetch("name") }
    assert_includes names, "Fowler, Refactoring"
    assert_includes names, "RuboCop Ruby Style Guide"
  end

  def test_rename_policy_covers_code_and_structure
    assert_equal %w[files constants methods variables rules sections], @plan.rename_policy.fetch("scopes")
    assert_equal true, @plan.rename_policy.fetch("require_reference_rewrite")
    assert_equal true, @plan.rename_policy.fetch("preserve_public_signatures")
  end

  def test_missing_policy_reports_source_and_available_sections
    original = Master.method(:load_laws)
    Master.define_singleton_method(:load_laws) { |_root:| { "prose" => {} } }

    error = assert_raises(ArgumentError) do
      Master::Fix::TransformationPlan.new(root: Master::ROOT)
    end

    assert_includes error.message, "transformation policy missing from #{File.join(Master::ROOT, "data", "laws.yml")}"
    assert_includes error.message, "available sections: prose"
  ensure
    Master.singleton_class.send(:define_method, :load_laws, original)
  end

  def test_unknown_operation_is_refused
    assert_raises(ArgumentError) { @plan.operation("invent") }
  end
end
