# frozen_string_literal: true

require_relative "test_helper"

class WhyExplainerTest < Minitest::Test
  def explainer
    Master::Trace::WhyExplainer.new(root: Master::ROOT)
  end

  def test_executable_law_resolves_from_repository_root
    out = Master::Trace::WhyExplainer.new(root: Master::REPO_ROOT)
      .send(:executable_law, "NO_VAR")

    assert_includes out, "executable law: NO_VAR"
  end

  def test_explain_law
    out = explainer.explain("ROBUSTNESS")
    assert_includes out, "law: ROBUSTNESS"
    assert_includes out, "priority:"
  end

  def test_explain_registry_law
    out = explainer.explain("DRY")
    assert_includes out, "law: DRY"
    assert_includes out, "Don't Repeat Yourself"
  end

  def test_explain_kernel_law_from_registry
    out = explainer.explain("BE_CONCISE")
    assert_includes out, "law: BE_CONCISE"
    assert_includes out, "tier: kernel"
  end

  def test_explain_soul_code_law_when_not_in_registry
    out = explainer.explain("NO_DEAD_ENDS")
    assert_includes out, "constitutional law: NO_DEAD_ENDS"
  end

  def test_explain_empty_returns_nil
    assert_nil explainer.explain("")
    assert_nil explainer.explain("   ")
  end

  def test_explain_path_returns_constitutional_lineage
    out = explainer.explain("lib/trace/why_explainer.rb")

    assert_includes out, "lineage: MASTER/lib/trace/why_explainer.rb"
    assert_includes out, "boundary: master"
    assert_includes out, "purpose: evidence, events, telemetry, replay, snapshots"
    assert_includes out, "status: RESOLVED"
    assert_includes out, "constitution: data/laws.yml"
    assert_includes out, "laws: ROBUSTNESS, SINGULARITY, LINEARITY, PROXIMITY, ABSTRACTION, DENSITY, RENDERED_VALUES"
    assert_includes out, "executable_law: law/"
  end

  def test_explain_path_uses_most_specific_ownership
    out = explainer.explain("lib/trace")

    assert_includes out, "purpose: evidence, events, telemetry, replay, snapshots"
    assert_includes out, "risk: high"
  end

  def test_explain_rails_path_returns_boundary_lineage
    out = explainer.explain("../RAILS/brgen/app/helpers/application_helper.rb")

    assert_includes out, "boundary: rails"
    assert_includes out, "entry: MASTER/bin/operator triangle"
    assert_includes out, "proof: MASTER/gates/runner.rb --all"
  end

  def test_explain_style_section
    out = explainer.explain("ruby.quotes")
    assert_includes out, "style: ruby.quotes"
    assert_includes out, "double"
  end
end
