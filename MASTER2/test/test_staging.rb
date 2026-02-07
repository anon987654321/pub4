# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../lib/master"

class TestStaging < Minitest::Test
  def setup
    @staging = MASTER::Staging.new(staging_dir: "tmp/test_staging")
    @test_file = "tmp/test_file_for_staging.rb"
    
    # Create test file
    FileUtils.mkdir_p("tmp")
    File.write(@test_file, "# Original content\nputs 'hello'\n")
  end

  def teardown
    # Cleanup
    FileUtils.rm_rf("tmp/test_staging")
    File.delete(@test_file) if File.exist?(@test_file)
  end

  def test_staging_dir_created
    assert Dir.exist?(@staging.staging_dir)
  end

  def test_stage_file_success
    result = @staging.stage_file(@test_file)
    
    assert result.ok?
    assert result.value[:staged_path]
    assert File.exist?(result.value[:staged_path])
    assert File.exist?(result.value[:backup])
  end

  def test_stage_file_missing
    result = @staging.stage_file("nonexistent.rb")
    
    refute result.ok?
    assert_match(/not found/, result.error)
  end

  def test_validate_success
    result = @staging.stage_file(@test_file)
    staged_path = result.value[:staged_path]
    
    validate_result = @staging.validate(staged_path, command: "ruby -c")
    assert validate_result.ok?
  end

  def test_validate_failure
    result = @staging.stage_file(@test_file)
    staged_path = result.value[:staged_path]
    
    # Write invalid Ruby
    File.write(staged_path, "def broken\nend end")
    
    validate_result = @staging.validate(staged_path, command: "ruby -c")
    refute validate_result.ok?
  end

  def test_promote_success
    stage_result = @staging.stage_file(@test_file)
    staged_path = stage_result.value[:staged_path]
    
    # Modify staged file
    File.write(staged_path, "# Modified\nputs 'world'\n")
    
    promote_result = @staging.promote(staged_path, @test_file)
    assert promote_result.ok?
    
    # Check original was updated
    assert_match(/Modified/, File.read(@test_file))
  end

  def test_rollback_success
    stage_result = @staging.stage_file(@test_file)
    staged_path = stage_result.value[:staged_path]
    
    # Modify original
    File.write(@test_file, "# Corrupted\n")
    
    rollback_result = @staging.rollback(@test_file)
    assert rollback_result.ok?
    
    # Check original was restored
    assert_match(/Original content/, File.read(@test_file))
  end

  def test_staged_modify_success_workflow
    result = @staging.staged_modify(@test_file, validation_command: "ruby -c") do |staged_path|
      File.write(staged_path, "# Modified via block\nputs 'test'\n")
    end
    
    assert result.ok?
    assert_match(/Modified via block/, File.read(@test_file))
  end

  def test_staged_modify_validation_failure_rollback
    original_content = File.read(@test_file)
    
    result = @staging.staged_modify(@test_file, validation_command: "ruby -c") do |staged_path|
      File.write(staged_path, "def broken\nend end")
    end
    
    refute result.ok?
    
    # Original should be unchanged
    assert_equal original_content, File.read(@test_file)
  end
end
