# frozen_string_literal: true

require_relative "test_helper"

class TestPlannerBasic < Minitest::Test
  def setup
    @planner = MASTER::Planner.new(nil) # No LLM needed for basic tests
  end

  def teardown
    @planner.clear_plan if @planner
  end

  # Test planner initialization
  def test_planner_initializes
    assert_instance_of MASTER::Planner, @planner
    assert_nil @planner.current_plan
  end

  # Test parse_tasks method extracts numbered steps
  def test_parse_tasks_extracts_numbered_steps
    text = <<~PLAN
      Here is my plan:
      1. Read the config file
      2. Analyze the data
      3. Generate report
      Done!
    PLAN
    
    tasks = @planner.send(:parse_tasks, text)
    assert_equal 3, tasks.size
    assert_equal "Read the config file", tasks[0][:action]
    assert_equal "Analyze the data", tasks[1][:action]
    assert_equal "Generate report", tasks[2][:action]
  end

  # Test parse_tasks handles different numbering formats
  def test_parse_tasks_handles_dot_and_paren
    text = <<~PLAN
      1. First task
      2) Second task
      3. Third task
    PLAN
    
    tasks = @planner.send(:parse_tasks, text)
    assert_equal 3, tasks.size
  end

  # Test parse_tasks strips command prefixes
  def test_parse_tasks_strips_command_prefixes
    text = "1. run: ls -la\n2. execute: pwd\n3. do: echo hello"
    tasks = @planner.send(:parse_tasks, text)
    
    assert_equal "ls -la", tasks[0][:action]
    assert_equal "pwd", tasks[1][:action]
    assert_equal "echo hello", tasks[2][:action]
  end

  # Test plan file constant
  def test_plan_file_constant_exists
    assert MASTER::Planner::PLAN_FILE.include?("current_plan.yml")
  end

  # Test max tasks limit
  def test_max_tasks_limit
    assert_equal 20, MASTER::Planner::MAX_TASKS
  end

  # Test progress returns nil when no plan
  def test_progress_returns_nil_without_plan
    assert_nil @planner.progress
  end

  # Test format_plan returns message when no plan
  def test_format_plan_returns_message_without_plan
    formatted = @planner.format_plan
    assert_includes formatted, "No active plan"
  end

  # Test next_task returns nil when no plan
  def test_next_task_returns_nil_without_plan
    assert_nil @planner.next_task
  end

  # Test clear_plan with no active plan
  def test_clear_plan_without_active_plan
    result = @planner.clear_plan
    assert result.ok?
  end

  # Test manual plan creation (without LLM)
  def test_manual_plan_creation
    # Manually create a plan structure
    @planner.instance_variable_set(:@current_plan, {
      goal: "Test goal",
      created_at: Time.now.iso8601,
      status: :pending,
      current_task: 0,
      tasks: [
        { action: "First task", status: :pending, retries: 0 },
        { action: "Second task", status: :pending, retries: 0 }
      ],
      results: []
    })
    
    # Test next_task
    task = @planner.next_task
    assert_equal "First task", task[:action]
    
    # Test progress
    progress = @planner.progress
    assert_equal "Test goal", progress[:goal]
    assert_equal "0/2", progress[:progress]
    assert_equal 0, progress[:percent]
  end

  # Test format_plan with manual plan
  def test_format_plan_with_plan
    @planner.instance_variable_set(:@current_plan, {
      goal: "Test formatting",
      created_at: Time.now.iso8601,
      status: :pending,
      current_task: 0,
      tasks: [
        { action: "Task 1", status: :complete, retries: 0 },
        { action: "Task 2", status: :pending, retries: 0 }
      ],
      results: []
    })
    
    formatted = @planner.format_plan
    assert_includes formatted, "Test formatting"
    assert_includes formatted, "Task 1"
    assert_includes formatted, "Task 2"
    assert_includes formatted, "50%"
  end
end
