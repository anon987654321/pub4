# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"

class TestSafeAutonomyIntegration < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @test_file = File.join(@test_dir, "sample.rb")
    File.write(@test_file, "puts 'original code'")
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    FileUtils.rm_rf(MASTER::Staging::STAGING_DIR) if Dir.exist?(MASTER::Staging::STAGING_DIR)
  end

  def test_constitution_exists_and_is_immutable
    const = MASTER::Executor.constitution
    assert const["immutable"], "Constitution should be marked as immutable"
    assert const.key?("tool_permissions"), "Constitution should define tool permissions"
    assert const.key?("principles"), "Constitution should define principles"
  end

  def test_planner_helper_generates_plan
    planner = MASTER::PlannerHelper.new
    # Test without LLM (just parsing)
    text = "1. First step\n2. Second step\n3. Third step"
    steps = planner.send(:parse_steps, text)
    assert_equal 3, steps.size
    assert_equal "First step", steps[0]
  end

  def test_executor_blocks_dangerous_file_writes
    executor = MASTER::Executor.new
    
    # Should block constitution write
    result = executor.send(:file_write, "data/constitution.yml", "bad content")
    assert_includes result, "BLOCKED"
    
    # Should block system directory writes
    result = executor.send(:file_write, "/etc/passwd", "bad content")
    assert_includes result, "BLOCKED"
  end

  def test_executor_blocks_dangerous_shell_commands
    executor = MASTER::Executor.new
    
    # Should block dangerous rm
    result = executor.send(:shell_command, "rm -rf /")
    assert_includes result, "BLOCKED"
    
    # Should allow safe commands
    result = executor.send(:shell_command, "echo test")
    assert_includes result.downcase, "test"
  end

  def test_executor_blocks_dangerous_code_execution
    executor = MASTER::Executor.new
    
    # Should block system calls
    result = executor.send(:code_execution, 'system("rm -rf /")')
    assert_includes result, "BLOCKED"
    
    # Should allow safe code
    result = executor.send(:code_execution, 'puts 2 + 2')
    assert_includes result, "4"
  end

  def test_staging_workflow_validates_before_promoting
    # Create a valid Ruby file
    File.write(@test_file, "puts 'valid code'")
    
    # Try to promote valid change
    result = MASTER::Staging.staged_workflow(@test_file, validation_command: "ruby -c {file}") do |staged_path|
      File.write(staged_path, "puts 'modified valid code'")
    end
    
    assert result.ok?, "Valid code should pass staging workflow"
    assert_equal "puts 'modified valid code'", File.read(@test_file)
  end

  def test_staging_workflow_rejects_invalid_code
    # Create a valid Ruby file
    File.write(@test_file, "puts 'valid code'")
    original_content = File.read(@test_file)
    
    # Try to promote invalid change
    result = MASTER::Staging.staged_workflow(@test_file, validation_command: "ruby -c {file}") do |staged_path|
      File.write(staged_path, "this is invalid ruby @@")
    end
    
    assert result.err?, "Invalid code should fail staging workflow"
    assert_includes result.error, "Validation failed"
    # Original file should be unchanged
    assert_equal original_content, File.read(@test_file)
  end

  def test_evolve_with_staging_option
    # This tests that Evolve can be instantiated with staged option
    # Note: We don't run it since it requires Chamber/LLM
    evolve = MASTER::Evolve.new(staged: true, validation_command: "ruby -c {file}")
    assert evolve.instance_variable_get(:@staged), "Evolve should accept staged option"
  end

  def test_permission_system_architecture
    # Verify the permission system components exist
    assert defined?(MASTER::Executor::CONSTITUTION_FILE)
    assert File.exist?(MASTER::Executor::CONSTITUTION_FILE)
    
    executor = MASTER::Executor.new
    assert executor.respond_to?(:check_shell_permission, true)
    assert executor.respond_to?(:check_code_execution_permission, true)
    assert executor.respond_to?(:check_file_write_permission, true)
  end

  def test_planner_helper_architecture
    # Verify planner helper exists and is separate from main Planner
    assert defined?(MASTER::PlannerHelper)
    assert defined?(MASTER::Planner)
    assert MASTER::PlannerHelper.respond_to?(:generate_plan)
  end

  def test_staging_architecture
    # Verify staging helper exists with proper methods
    assert defined?(MASTER::Staging)
    staging = MASTER::Staging.new(@test_file)
    assert staging.respond_to?(:stage)
    assert staging.respond_to?(:validate)
    assert staging.respond_to?(:promote)
    assert staging.respond_to?(:rollback)
    assert staging.respond_to?(:cleanup)
  end
end
