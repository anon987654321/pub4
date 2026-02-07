# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPlannerHelper < Minitest::Test
  def setup
    @planner = MASTER::PlannerHelper.new
  end

  def test_exists
    assert defined?(MASTER::PlannerHelper)
  end

  def test_max_steps_constant
    assert_equal 20, MASTER::PlannerHelper::MAX_STEPS
  end

  def test_class_method_exists
    assert MASTER::PlannerHelper.respond_to?(:generate_plan)
  end

  def test_parse_steps_numbered_items
    text = <<~PLAN
      Here is the plan:
      1. Read the file
      2. Analyze the code
      3. Fix any issues
      4. Run tests
    PLAN

    steps = @planner.send(:parse_steps, text)
    assert_equal 4, steps.size
    assert_equal "Read the file", steps[0]
    assert_equal "Analyze the code", steps[1]
    assert_equal "Fix any issues", steps[2]
    assert_equal "Run tests", steps[3]
  end

  def test_parse_steps_with_parentheses
    text = <<~PLAN
      1) First step
      2) Second step
      3) Third step
    PLAN

    steps = @planner.send(:parse_steps, text)
    assert_equal 3, steps.size
    assert_equal "First step", steps[0]
  end

  def test_parse_steps_with_colons
    text = <<~PLAN
      1: Check configuration
      2: Update dependencies
    PLAN

    steps = @planner.send(:parse_steps, text)
    assert_equal 2, steps.size
    assert_equal "Check configuration", steps[0]
  end

  def test_parse_steps_cleans_prefixes
    text = <<~PLAN
      1. Step: Read the file
      2. Action: Process data
      3. Task: Write results
    PLAN

    steps = @planner.send(:parse_steps, text)
    assert_equal 3, steps.size
    assert_equal "Read the file", steps[0]
    assert_equal "Process data", steps[1]
    assert_equal "Write results", steps[2]
  end

  def test_parse_steps_ignores_unnumbered
    text = <<~PLAN
      Here is a plan:
      1. First step
      Some random text
      2. Second step
      More text here
    PLAN

    steps = @planner.send(:parse_steps, text)
    assert_equal 2, steps.size
  end

  def test_parse_steps_respects_max_limit
    text = (1..30).map { |i| "#{i}. Step #{i}" }.join("\n")
    steps = @planner.send(:parse_steps, text)
    assert_equal 20, steps.size  # MAX_STEPS limit
  end

  def test_parse_steps_empty_for_no_matches
    text = "No numbered steps here"
    steps = @planner.send(:parse_steps, text)
    assert_equal 0, steps.size
  end

  def test_build_planning_prompt
    prompt = @planner.send(:build_planning_prompt, "Deploy the application")
    assert_includes prompt, "Deploy the application"
    assert_includes prompt, "GOAL:"
    assert_includes prompt, "step-by-step"
    assert_includes prompt, "20"  # MAX_STEPS
  end
end
