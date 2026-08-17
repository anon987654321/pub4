# frozen_string_literal: true

require_relative "test_helper"

# The Ruby loc ratchet never watched YAML, which is how rules.yml burned down
# twice and grew back. This is that file's budget, read from the same key
# rake loc_budget now counts as a file path.
class TestYamlLocBudget < Minitest::Test
  def test_rules_yml_is_under_its_file_budget
    limits = YAML.safe_load_file(Master.limits_path, aliases: true)
    budget = limits.dig("loc_budgets", "data/rules.yml")
    actual = File.foreach(Master.data_path("rules.yml")).count

    refute_nil budget, "loc_budgets.data/rules.yml must exist"
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
