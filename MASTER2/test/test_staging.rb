# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require_relative "../lib/master"

class TestStaging < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
    @staging = MASTER::Staging.new
    @test_dir = Dir.mktmpdir
    @test_file = File.join(@test_dir, "test.rb")
    File.write(@test_file, "puts 'original'")
  end
  
  def teardown
    @staging.cleanup
    FileUtils.rm_rf(@test_dir) if @test_dir
  end
  
  def test_stage_file_creates_staging_copy
    result = @staging.stage_file(@test_file)
    
    assert result.ok?, "Staging should succeed"
    assert File.exist?(result.value[:staged_path]), "Staged file should exist"
    assert_equal @test_file, result.value[:original_path], "Should track original path"
  end
  
  def test_stage_file_creates_backup
    @staging.stage_file(@test_file)
    
    refute_empty @staging.backups, "Should create backup"
    assert @staging.backups.key?(@test_file), "Should have backup for original file"
    assert File.exist?(@staging.backups[@test_file]), "Backup file should exist"
  end
  
  def test_validate_with_valid_ruby
    result = @staging.stage_file(@test_file)
    staged_path = result.value[:staged_path]
    
    validation = @staging.validate(staged_path)
    assert validation.ok?
    assert validation.value[:results].all? { |r| r[:success] }
  end
  
  def test_validate_with_invalid_ruby
    result = @staging.stage_file(@test_file)
    staged_path = result.value[:staged_path]
    
    # Write invalid Ruby
    File.write(staged_path, "this is not valid ruby {{{")
    
    validation = @staging.validate(staged_path)
    refute validation.ok?
    assert_match(/Validation failed/, validation.error)
    assert_match(/ruby -c/, validation.error)
  end
  
  def test_promote_replaces_original_file
    result = @staging.stage_file(@test_file)
    staged_path = result.value[:staged_path]
    original_path = result.value[:original_path]
    
    # Modify staged file
    new_content = "puts 'modified'"
    File.write(staged_path, new_content)
    
    promote_result = @staging.promote(staged_path, original_path)
    assert promote_result.ok?, "Promotion should succeed"
    assert_equal new_content, File.read(@test_file), "Original should have new content"
  end
  
  def test_rollback_restores_original
    result = @staging.stage_file(@test_file)
    original_content = File.read(@test_file)
    
    # Modify original
    File.write(@test_file, "puts 'broken'")
    
    rollback_result = @staging.rollback(@test_file)
    assert rollback_result.ok?, "Rollback should succeed"
    assert_equal original_content, File.read(@test_file), "Should restore original content"
  end
  
  def test_staged_modify_workflow_success
    result = @staging.staged_modify(@test_file) do |staged_path|
      File.write(staged_path, "puts 'valid modification'")
    end
    
    assert result.ok?, "Staged modify should succeed"
    assert result.value[:validated], "Should be validated"
    assert result.value[:promoted], "Should be promoted"
    assert_equal "puts 'valid modification'", File.read(@test_file), "File should be modified"
  end
  
  def test_staged_modify_workflow_validation_failure
    original_content = File.read(@test_file)
    staged_content = "invalid ruby {{{"
    
    result = @staging.staged_modify(@test_file) do |staged_path|
      File.write(staged_path, staged_content)
    end
    
    refute result.ok?
    assert_equal original_content, File.read(@test_file)
    # Verify staging was cleaned up or rolled back
    assert_match(/Validation failed/, result.error)
  end
  
  def test_staged_modify_workflow_modification_error
    original_content = File.read(@test_file)
    
    result = @staging.staged_modify(@test_file) do |staged_path|
      raise "Intentional error"
    end
    
    refute result.ok?
    assert_match(/Modification failed/, result.error)
    assert_equal original_content, File.read(@test_file)
  end
  
  def test_cleanup_removes_staging_directory
    @staging.stage_file(@test_file)
    staging_dir = @staging.staging_dir
    
    assert File.exist?(staging_dir), "Staging dir should exist before cleanup"
    
    @staging.cleanup
    refute File.exist?(staging_dir), "Staging dir should be removed after cleanup"
    assert_empty @staging.backups, "Backups should be cleared"
  end
end
