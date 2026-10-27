# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/run_ledger"

# The times a /fix run allows come from data/limits.yml#fix_time for the lane it is pinned to.
class FixTimeTest < Minitest::Test
  Budget = Master::Fix::FixTime
  OPUS = "claude-cli:claude-opus-5-5"

  def setup
    @saved = Budget::KEYS.values.to_h { |key| [key, ENV.delete(key)] }
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_a_run_pinned_to_claude_cli_gets_the_times_opus_takes
    assert_equal [900, 7200, 900], [Budget.file_s(model: OPUS), Budget.run_s(model: OPUS), Budget.stall_s(model: OPUS)]
  end

  def test_a_run_with_no_pin_or_an_unlisted_lane_gets_the_default
    assert_equal 240, Budget.file_s(model: nil)
    assert_equal 1800, Budget.run_s(model: "grok-cli:auto")
  end

  def test_the_environment_overrides_one_run
    ENV["MASTER_FIX_FILE_BUDGET_S"] = "7"

    assert_equal 7, Budget.file_s(model: OPUS)
  end
end
