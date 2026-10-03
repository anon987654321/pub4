# frozen_string_literal: true

require_relative "test_helper"

# The Ruby loc ratchet never watched YAML, which is how rules.yml burned down
# twice and grew back. This is that file's budget, read from the same key
# rake loc_budget counts as a file path.
#
# Both the key and the unit moved on 2026-08-25: loc_budgets counted raw lines,
# loc_body_budgets counts body lines. For a YAML file that is non-blank
# non-comment — CodeMetrics.namespace_lines finds nothing to exempt because
# Prism cannot parse YAML and says so rather than guessing.
class TestYamlLocBudget < Minitest::Test
  def test_rules_yml_is_under_its_file_budget
    limits = YAML.safe_load_file(Master.limits_path, aliases: true)
    budget = limits.dig("loc_body_budgets", "data/rules.yml")
    actual = Master::Review::Scan::CodeMetrics.body_lines(File.read(Master.data_path("rules.yml")))

    refute_nil budget, "loc_body_budgets.data/rules.yml must exist"
    assert_operator actual, :<=, budget,
                    "data/rules.yml is #{actual} lines, budget #{budget} — shrink, do not raise"
  end

  def test_forbidden_basenames_match_the_guidance_list
    guidance = YAML.safe_load_file(Master.limits_path, aliases: true)
                   .dig("guidance", "anti_sprawl", "forbidden_files")
    assert_equal guidance.map(&:downcase).sort,
                 Master::Core::Constitution::FORBIDDEN_BASENAMES.sort
  end
end
