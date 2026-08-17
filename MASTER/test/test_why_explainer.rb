# frozen_string_literal: true

require_relative "test_helper"

class WhyExplainerTest < Minitest::Test
  def explainer
    Master::Trace::WhyExplainer.new(root: Master::ROOT)
  end

  def test_explain_law
    out = explainer.explain("ROBUSTNESS")
    assert_includes out, "law: ROBUSTNESS"
    assert_includes out, "priority:"
  end

  def test_explain_registry_rule
    out = explainer.explain("DRY")
    assert_includes out, "rule: DRY"
    assert_includes out, "Don't Repeat Yourself"
  end

  def test_explain_kernel_rule_from_registry
    out = explainer.explain("BE_CONCISE")
    assert_includes out, "rule: BE_CONCISE"
    assert_includes out, "tier: kernel"
  end

  def test_explain_soul_code_rule_when_not_in_registry
    out = explainer.explain("NO_DEAD_ENDS")
    assert_includes out, "constitutional rule: NO_DEAD_ENDS"
  end

  def test_explain_empty_returns_nil
    assert_nil explainer.explain("")
    assert_nil explainer.explain("   ")
  end

  def test_explain_style_section
    out = explainer.explain("ruby.quotes")
    assert_includes out, "style: ruby.quotes"
    assert_includes out, "double"
  end
end
