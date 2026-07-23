# frozen_string_literal: true

require_relative "test_helper"

class TestDispatchLaws < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  def test_no_arg_lists_all_eight_laws
    report = Registry.dispatch_laws(root: Master::ROOT, ctx: { args: "" })

    %w[ROBUSTNESS SINGULARITY LINEARITY PROXIMITY ABSTRACTION DENSITY KERNEL_ADHERENCE PRINCIPLE_MAP].each do |law|
      assert_includes report, law
    end
  end

  def test_known_law_returns_meaning_and_enforcing_method
    report = Registry.dispatch_laws(root: Master::ROOT, ctx: { args: "PROXIMITY" })

    assert_includes report, "PROXIMITY"
    assert_includes report, "test files within 1 directory of source"
    assert_includes report, "enforced by:"
  end

  def test_unknown_law_gives_a_helpful_message
    report = Registry.dispatch_laws(root: Master::ROOT, ctx: { args: "NOT_A_LAW" })

    assert_includes report, "unknown law"
    assert_includes report, "/laws"
  end

  def test_laws_report_matches_data_rules_yml_exactly
    laws = Master.load_yaml(File.join(Master::ROOT, "data", "rules.yml")).dig("self_test", "laws_apply_to_self")
    report = Registry.dispatch_laws(root: Master::ROOT, ctx: { args: "" })

    laws.each { |law, meaning| assert_includes report, "#{law}", "#{law}: #{meaning}" }
  end
end
