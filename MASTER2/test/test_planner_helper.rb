# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPlannerHelper < Minitest::Test
  def test_parse_plan_with_numbered_list
    text = <<~PLAN
      Here's the plan:
      1. First step
      2. Second step
      3. Third step
    PLAN
    
    steps = MASTER::PlannerHelper.parse_plan(text)
    
    assert_equal 3, steps.size
    assert_equal "First step", steps[0]
    assert_equal "Second step", steps[1]
    assert_equal "Third step", steps[2]
  end

  def test_parse_plan_with_parenthesis
    text = <<~PLAN
      1) First step
      2) Second step
    PLAN
    
    steps = MASTER::PlannerHelper.parse_plan(text)
    
    assert_equal 2, steps.size
    assert_equal "First step", steps[0]
  end

  def test_parse_plan_empty
    steps = MASTER::PlannerHelper.parse_plan("")
    assert_equal [], steps
  end

  def test_parse_plan_nil
    steps = MASTER::PlannerHelper.parse_plan(nil)
    assert_equal [], steps
  end

  def test_generate_plan_requires_goal
    result = MASTER::PlannerHelper.generate_plan("")
    refute result.ok?
  end

  def test_generate_plan_returns_result
    skip "Requires LLM module"
    
    # This would test actual plan generation
    # result = MASTER::PlannerHelper.generate_plan("Build a web server")
    # assert result.ok?
    # assert result.value[:steps].is_a?(Array)
  end
end
