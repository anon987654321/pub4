# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "open3"

module MASTER
  class Staging
    attr_reader :staging_dir

    def initialize(staging_dir: nil)
      @staging_dir = staging_dir || File.join(MASTER.root, "tmp", "staging")
      @backups = {}
      FileUtils.mkdir_p(@staging_dir)
    end

    def stage_file(path)
      return Result.err("File not found: #{path}") unless File.exist?(path)

      basename = File.basename(path)
      staged_path = File.join(@staging_dir, "#{Time.now.to_i}_#{basename}")
      
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

    def validate(staged_path, command: nil)
      return Result.err("Staged file not found: #{staged_path}") unless File.exist?(staged_path)

      validation_cmd = command
      if validation_cmd.nil? && defined?(Constitution)
        validation_cmd = Constitution.rules.dig("staging", "validation", "default_command")
      end
      validation_cmd ||= "ruby -c"

      begin
        stdout, stderr, status = Open3.capture3("#{validation_cmd} #{staged_path}")
        
        if status.success?
          Result.ok(output: stdout)
        else
          Result.err("Validation failed: #{stderr}")
        end
      rescue StandardError => e
        Result.err("Validation error: #{e.message}")
      end
    end

    def promote(staged_path, original_path)
      return Result.err("Staged file not found: #{staged_path}") unless File.exist?(staged_path)

      begin
        FileUtils.cp(staged_path, original_path)
        Result.ok(promoted: original_path)
      rescue StandardError => e
        Result.err("Failed to promote: #{e.message}")
      end
    end

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

    def rollback_all
      return Result.err("No backups to rollback") if @backups.empty?
      
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

    def backups
      @backups.keys
    end

    def staged_modify(path, validation_command: nil, &block)
      stage_result = stage_file(path)
      return stage_result unless stage_result.ok?
      
      staged_path = stage_result.value[:staged_path]
      
      begin
        block.call(staged_path) if block
        
        validate_result = validate(staged_path, command: validation_command)
        unless validate_result.ok?
          rollback(path)
          return validate_result
        end
        
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
        FileUtils.rm_f(staged_path) if staged_path && File.exist?(staged_path)
      end
    end
  end
end
