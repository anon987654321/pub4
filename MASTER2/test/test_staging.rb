# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"

class TestStaging < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @test_file = File.join(@test_dir, "test.rb")
    File.write(@test_file, "puts 'original'")
    @staging = MASTER::Staging.new(@test_file)
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    FileUtils.rm_rf(MASTER::Staging::STAGING_DIR) if Dir.exist?(MASTER::Staging::STAGING_DIR)
  end

  def test_exists
    assert defined?(MASTER::Staging)
  end

  def test_staging_dir_constant
    assert defined?(MASTER::Staging::STAGING_DIR)
    assert MASTER::Staging::STAGING_DIR.include?("master_staging")
  end

  def test_initialize_sets_paths
    assert_equal @test_file, @staging.original_path
    assert_includes @staging.staging_path, "test.rb"
    assert_includes @staging.backup_path, ".backup"
  end

  def test_initialize_rejects_nonexistent_path
    assert_raises(ArgumentError) do
      MASTER::Staging.new("/nonexistent/path/file.rb")
    end
  end

  def test_stage_copies_file
    result = @staging.stage
    assert result.ok?
    assert File.exist?(@staging.staging_path)
    assert_equal File.read(@test_file), File.read(@staging.staging_path)
  end

  def test_validate_with_passing_command
    @staging.stage
    result = @staging.validate(command: "ruby -c {file}")
    assert result.ok?
  end

  def test_validate_with_failing_command
    @staging.stage
    # Write invalid Ruby to staged file
    File.write(@staging.staging_path, "this is not valid ruby syntax @@")
    result = @staging.validate(command: "ruby -c {file}")
    assert result.err?
  end

  def test_validate_with_block_passing
    @staging.stage
    result = @staging.validate { |path| File.exist?(path) }
    assert result.ok?
  end

  def test_validate_with_block_failing
    @staging.stage
    result = @staging.validate { |_| false }
    assert result.err?
  end

  def test_validate_with_block_exception
    @staging.stage
    result = @staging.validate { |_| raise "Validation error" }
    assert result.err?
    assert_includes result.error, "Validation error"
  end

  def test_validate_without_staged_file
    result = @staging.validate(command: "ruby -c {file}")
    assert result.err?
    assert_includes result.error, "No staged file"
  end

  def test_promote_copies_to_original
    @staging.stage
    File.write(@staging.staging_path, "puts 'modified'")
    
    result = @staging.promote
    assert result.ok?
    assert_equal "puts 'modified'", File.read(@test_file)
  end

  def test_promote_creates_backup
    @staging.stage
    File.write(@staging.staging_path, "puts 'modified'")
    
    result = @staging.promote(backup: true)
    assert result.ok?
    assert File.exist?(@staging.backup_path)
    assert_equal "puts 'original'", File.read(@staging.backup_path)
  end

  def test_promote_without_backup
    @staging.stage
    File.write(@staging.staging_path, "puts 'modified'")
    
    result = @staging.promote(backup: false)
    assert result.ok?
    refute File.exist?(@staging.backup_path)
  end

  def test_promote_without_staged_file
    result = @staging.promote
    assert result.err?
    assert_includes result.error, "No staged file"
  end

  def test_rollback_restores_backup
    @staging.stage
    File.write(@staging.staging_path, "puts 'modified'")
    @staging.promote(backup: true)
    
    # Verify file was changed
    assert_equal "puts 'modified'", File.read(@test_file)
    
    # Rollback
    result = @staging.rollback
    assert result.ok?
    assert_equal "puts 'original'", File.read(@test_file)
  end

  def test_rollback_without_backup
    result = @staging.rollback
    assert result.err?
    assert_includes result.error, "No backup"
  end

  def test_cleanup_removes_files
    @staging.stage
    @staging.promote(backup: true)
    
    assert File.exist?(@staging.staging_path)
    assert File.exist?(@staging.backup_path)
    
    result = @staging.cleanup
    assert result.ok?
    refute File.exist?(@staging.staging_path)
    refute File.exist?(@staging.backup_path)
  end

  def test_staged_workflow_with_validation
    result = MASTER::Staging.staged_workflow(@test_file, validation_command: "ruby -c {file}") do |staged_path|
      File.write(staged_path, "puts 'workflow modified'")
    end
    
    assert result.ok?
    assert_equal "puts 'workflow modified'", File.read(@test_file)
  end

  def test_staged_workflow_with_validation_failure
    result = MASTER::Staging.staged_workflow(@test_file, validation_command: "ruby -c {file}") do |staged_path|
      File.write(staged_path, "invalid ruby @@")
    end
    
    assert result.err?
    assert_includes result.error, "Validation failed"
    # Original file should be unchanged
    assert_equal "puts 'original'", File.read(@test_file)
  end

  def test_staged_workflow_without_validation
    result = MASTER::Staging.staged_workflow(@test_file) do |staged_path|
      File.write(staged_path, "puts 'no validation'")
    end
    
    assert result.ok?
    assert_equal "puts 'no validation'", File.read(@test_file)
  end

  def test_staged_workflow_with_modifier_error
    result = MASTER::Staging.staged_workflow(@test_file) do |_|
      raise "Modification error"
    end
    
    assert result.err?
    assert_includes result.error, "Modification failed"
    # Original file should be unchanged
    assert_equal "puts 'original'", File.read(@test_file)
  end

  def test_staged_workflow_returns_metadata
    result = MASTER::Staging.staged_workflow(@test_file, validation_command: "ruby -c {file}", backup: true) do |staged_path|
      File.write(staged_path, "puts 'metadata test'")
    end
    
    assert result.ok?
    assert_equal @test_file, result.value[:path]
    assert_equal true, result.value[:staged]
    assert_equal true, result.value[:validated]
    assert_equal true, result.value[:backup]
  end
end
