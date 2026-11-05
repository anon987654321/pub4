# frozen_string_literal: true

# The constants and readers check_live_and_css_budget_test.rb shares with the tests split
# out of it to keep each file under its length ceiling.
module CheckLiveAndCssBudgetSources
  def teardown
    ENV.delete("CHECK_REQUIRE_LIVE")
  end

  def with_env(pairs)
    previous = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def result_with_skip
    result = Deploy::CheckResult.new
    result.checked!(50)
    result.skipped_live("brgen port closed")
    result
  end

  def design_tokens
    Operator::MasterDesign.tokens
  end

  def budget
    YAML.safe_load_file(File.expand_path("../../../MASTER/checks/data/css_budget.yml", __dir__)).fetch("rules")
  end

  def rhythm_check
    check = Deploy::CssConstitutionCheck.new
    check.instance_variable_set(:@design, Operator::MasterDesign.blocks(Deploy::CssConstitutionCheck::MASTER_DESIGN))
    check.instance_variable_set(:@tally, { "important" => [], "rhythm" => [], "magic_hex" => [], "type_scale" => [], "weight_ladder" => [] })
    check
  end

  def spacing_check
    check = Deploy::CssConstitutionCheck.new
    check.instance_variable_set(:@tally, {
      "important" => [], "rhythm" => [], "magic_hex" => [],
      "type_scale" => [], "weight_ladder" => [],
      "child_margin" => [], "card_padding" => []
    })
    check
  end
end
