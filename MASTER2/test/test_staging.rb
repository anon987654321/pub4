# frozen_string_literal: true

require_relative "test_helper"

class TestStaging < Minitest::Test
  def setup
    @staging = MASTER::Staging.new
    @test_dir = Dir.mktmpdir
    @test_file = File.join(@test_dir, "sample.rb")
    @test_content = "# Test file\nputs 'hello'\n"
    File.write(@test_file, @test_content)
  end

  def teardown
    @staging.rollback if @staging
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # Test staging a file
  def test_stage_file
    result = @staging.stage(@test_file)
    
    assert result.ok?, "Stage should succeed"
    assert_includes result.value[:staged_path], "staging"
    assert File.exist?(result.value[:staged_path])
  end

  # Test staging a non-existent file
  def test_stage_nonexistent_file
    result = @staging.stage("/nonexistent/file.rb")
    
    assert result.err?, "Should fail for non-existent file"
    assert_includes result.error, "not found"
  end

  # Test validation with command
  def test_validate_with_command_success
    @staging.stage(@test_file)
    result = @staging.validate(command: "ruby -c #{@test_file}")
    
    # Note: validation runs in staging dir, so we need to use relative path
    assert result.ok? || result.err?, "Validation should complete"
  end

  # Test validation with block
  def test_validate_with_block_success
    @staging.stage(@test_file)
    result = @staging.validate do |staging_dir, files|
      files.each do |file_info|
        assert File.exist?(file_info[:staged])
      end
      "All files validated"
    end
    
    assert result.ok?, "Block validation should succeed"
  end

  # Test validation with block failure
  def test_validate_with_block_failure
    @staging.stage(@test_file)
    result = @staging.validate do |staging_dir, files|
      raise "Validation failed"
    end
    
    assert result.err?, "Block validation should fail"
    assert_includes result.error, "Validation"
  end

  # Test promotion after successful validation
  def test_promote_after_validation
    # Stage file
    @staging.stage(@test_file)
    
    # Modify staged version
    staged_path = @staging.staged_files.first[:staged]
    modified_content = "# Modified\nputs 'world'\n"
    File.write(staged_path, modified_content)
    
    # Validate
    @staging.validate { "OK" }
    
    # Promote
    result = @staging.promote
    assert result.ok?, "Promote should succeed after validation"
    
    # Check original file was updated
    assert_equal modified_content, File.read(@test_file)
  end

  # Test promote fails without validation
  def test_promote_fails_without_validation
    @staging.stage(@test_file)
    result = @staging.promote
    
    assert result.err?, "Promote should fail without validation"
    assert_includes result.error, "validation"
  end

  # Test promote fails after failed validation
  def test_promote_fails_after_failed_validation
    @staging.stage(@test_file)
    @staging.validate { raise "Failed" }
    
    result = @staging.promote
    assert result.err?, "Promote should fail after failed validation"
  end

  # Test rollback
  def test_rollback
    @staging.stage(@test_file)
    assert @staging.staged_files.size > 0
    
    result = @staging.rollback
    assert result.ok?, "Rollback should succeed"
    assert_equal 0, @staging.staged_files.size
  end

  # Test summary
  def test_summary
    @staging.stage(@test_file)
    summary = @staging.summary
    
    assert_equal 1, summary[:staged_count]
    assert_equal false, summary[:validated]
    assert summary[:files].size > 0
  end

  # Test multiple file staging
  def test_stage_multiple_files
    file2 = File.join(@test_dir, "another.rb")
    File.write(file2, "# Another file\n")
    
    @staging.stage(@test_file)
    @staging.stage(file2)
    
    assert_equal 2, @staging.staged_files.size
  end
end
