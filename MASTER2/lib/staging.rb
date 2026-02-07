# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "open3"

module MASTER
  # Staging - Staged self-refactor with validation and rollback
  # Copies files to staging, validates, then promotes on success
  class Staging
    STAGING_DIR = File.join(Dir.tmpdir, "master_staging")
    
    attr_reader :staging_path, :original_path, :backup_path
    
    def initialize(path)
      @original_path = File.expand_path(path)
      raise ArgumentError, "Path does not exist: #{path}" unless File.exist?(@original_path)
      
      @staging_path = File.join(STAGING_DIR, File.basename(@original_path))
      @backup_path = "#{@original_path}.backup"
    end
    
    # Stage a file: copy to staging directory
    def stage
      FileUtils.mkdir_p(STAGING_DIR)
      FileUtils.cp(@original_path, @staging_path)
      Result.ok(staged: @staging_path)
    rescue StandardError => e
      Result.err("Failed to stage: #{e.message}")
    end
    
    # Validate staged file with command or block
    def validate(command: nil, &block)
      return Result.err("No staged file") unless File.exist?(@staging_path)
      
      if block_given?
        begin
          result = block.call(@staging_path)
          result ? Result.ok(validation: :passed) : Result.err("Validation block returned false")
        rescue StandardError => e
          Result.err("Validation failed: #{e.message}")
        end
      elsif command
        result = run_validation_command(command)
        result
      else
        Result.err("No validation method provided")
      end
    end
    
    # Promote staged file to original (with backup)
    def promote(backup: true)
      return Result.err("No staged file") unless File.exist?(@staging_path)
      
      begin
        # Create backup if requested
        if backup && File.exist?(@original_path)
          FileUtils.cp(@original_path, @backup_path)
        end
        
        # Promote staged file
        FileUtils.cp(@staging_path, @original_path)
        
        Result.ok(promoted: @original_path, backup: backup ? @backup_path : nil)
      rescue StandardError => e
        Result.err("Failed to promote: #{e.message}")
      end
    end
    
    # Rollback: restore from backup
    def rollback
      return Result.err("No backup found") unless File.exist?(@backup_path)
      
      begin
        FileUtils.cp(@backup_path, @original_path)
        Result.ok(restored: @original_path)
      rescue StandardError => e
        Result.err("Failed to rollback: #{e.message}")
      end
    end
    
    # Cleanup: remove staged and backup files
    def cleanup
      FileUtils.rm_f(@staging_path) if File.exist?(@staging_path)
      FileUtils.rm_f(@backup_path) if File.exist?(@backup_path)
      Result.ok(cleaned: true)
    end
    
    # Full staged workflow: stage -> modify -> validate -> promote
    def self.staged_workflow(path, validation_command: nil, backup: true, &modifier)
      staging = new(path)
      
      # Stage
      result = staging.stage
      return result unless result.ok?
      
      # Modify (if block provided)
      if block_given?
        begin
          modifier.call(staging.staging_path)
        rescue StandardError => e
          staging.cleanup
          return Result.err("Modification failed: #{e.message}")
        end
      end
      
      # Validate
      if validation_command
        result = staging.validate(command: validation_command)
        unless result.ok?
          staging.cleanup
          return Result.err("Validation failed: #{result.error}")
        end
      end
      
      # Promote
      result = staging.promote(backup: backup)
      return result unless result.ok?
      
      # Cleanup
      staging.cleanup
      
      Result.ok(
        path: path,
        staged: true,
        validated: !validation_command.nil?,
        backup: backup
      )
    end
    
    private
    
    def run_validation_command(command)
      # Replace {file} placeholder with staged path
      cmd = command.gsub(/\{file\}/, @staging_path)
      
      stdout, stderr, status = Open3.capture3(cmd)
      
      if status.success?
        Result.ok(validation: :passed, output: stdout)
      else
        Result.err("Validation command failed: #{stderr}")
      end
    end
  end
end
