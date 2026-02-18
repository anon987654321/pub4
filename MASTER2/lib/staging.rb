# frozen_string_literal: true

require "fileutils"
require "open3"

module MASTER
  # Staging - Safe file modification workflow with validation and rollback
  class Staging
    attr_reader :staging_dir

    def initialize(staging_dir: nil)
      @staging_dir = staging_dir || File.join(MASTER.root, "tmp", "staging")
      @backups = {}
      FileUtils.mkdir_p(@staging_dir)
    end

    # Stage a file for modification
    def stage_file(path)
      return Result.err("File not found: #{path}") unless File.exist?(path)

      # Create unique staging path
      basename = File.basename(path)
      staged_path = File.join(@staging_dir, "#{Time.now.to_i}_#{basename}")

      # Create backup of original
      backup_path = "#{staged_path}.backup"

      begin
        FileUtils.cp(path, staged_path)
        FileUtils.cp(path, backup_path)
        @backups[path] = backup_path

        Result.ok(staged_path: staged_path, backup: backup_path)
      rescue StandardError => e
        Result.err("Failed to stage file: #{e.message}")
      end
    end

    # Validate a staged file
    def validate(staged_path, command: nil)
      return Result.err("Staged file not found: #{staged_path}") unless File.exist?(staged_path)

      # Get validation command from constitution or use provided
      validation_cmd = command
      if validation_cmd.nil? && defined?(Constitution)
        validation_cmd = Constitution.rules.dig("staging", "validation", "default_command")
      end
      validation_cmd ||= "ruby -c"

      begin
        # Run validation command with array form to prevent shell injection
        stdout, stderr, status = Open3.capture3(validation_cmd, staged_path)

        if status.success?
          Result.ok(output: stdout)
        else
          Result.err("Validation failed: #{stderr}")
        end
      rescue StandardError => e
        Result.err("Validation error: #{e.message}")
      end
    end

    # Promote staged file to original location
    def promote(staged_path, original_path)
      return Result.err("Staged file not found: #{staged_path}") unless File.exist?(staged_path)

      temp_path = nil
      begin
        # Atomic replace: create temp file on same filesystem, then rename
        original_dir = File.dirname(original_path)
        temp_path = File.join(original_dir, ".tmp_#{Time.now.to_i}_#{File.basename(original_path)}")

        # Copy to temp location on same filesystem
        FileUtils.cp(staged_path, temp_path)

        # Atomic rename (POSIX guarantee)
        File.rename(temp_path, original_path)

        Result.ok(promoted: original_path)
      rescue StandardError => e
        # Clean up temp file if it exists
        begin
          File.unlink(temp_path) if temp_path && File.exist?(temp_path)
        rescue StandardError
          # Ignore cleanup errors
        end
        Result.err("Failed to promote: #{e.message}")
      end
    end

    # Rollback to backup
    def rollback(original_path)
      backup_path = @backups[original_path]
      return Result.err("No backup found for: #{original_path}") unless backup_path && File.exist?(backup_path)

      begin
        FileUtils.cp(backup_path, original_path)
        Result.ok(restored: original_path)
      rescue StandardError => e
        Result.err("Failed to rollback: #{e.message}")
      end
    end

    # Rollback all files modified in this staging session
    def rollback_all
      return Result.err("No backups to rollback.") if @backups.empty?

      results = []
      @backups.each do |original_path, backup_path|
        result = rollback(original_path)
        results << { path: original_path, success: result.ok?, error: result.error }
      end

      successes = results.count { |r| r[:success] }
      failures = results.reject { |r| r[:success] }

      if successes == results.size
        Result.ok(restored: successes, details: results)
      else
        failed_paths = failures.map { |f| f[:path] }.join(", ")
        Result.err("Partial rollback: #{successes}/#{results.size} succeeded. Failed: #{failed_paths}")
      end
    end

    # Get list of all backed-up files
    def backups
      @backups.keys
    end

    # Full staged modification workflow
    def staged_modify(path, validation_command: nil, &block)
      # Stage the file
      stage_result = stage_file(path)
      return stage_result unless stage_result.ok?

      staged_path = stage_result.value[:staged_path]

      begin
        # Yield to the block for modification
        block.call(staged_path) if block

        # Validate the changes
        validate_result = validate(staged_path, command: validation_command)
        unless validate_result.ok?
          rollback(path)
          return validate_result
        end

        # Promote to original location
        promote_result = promote(staged_path, path)
        unless promote_result.ok?
          rollback(path)
          return promote_result
        end

        Result.ok(modified: path)
      rescue StandardError => e
        rollback(path)
        Result.err("Staged modification failed: #{e.message}")
      ensure
        # Cleanup staging file
        FileUtils.rm_f(staged_path) if staged_path && File.exist?(staged_path)
      end
    end
  end
end
