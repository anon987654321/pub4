# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module MASTER
  # Staging - Staged self-refactor helper
  # Copies files to a staging directory, validates, and promotes on success
  class Staging
    STAGING_DIR = File.join(Paths.var, 'staging')
    
    attr_reader :staged_files, :validation_results
    
    def initialize
      @staged_files = []
      @validation_results = []
      ensure_staging_dir
    end
    
    # Stage a file or directory to the staging area
    # Returns Result with staged path
    def stage(path)
      return Result.err("Path not found: #{path}") unless File.exist?(path)
      
      expanded = File.expand_path(path)
      relative = expanded.sub(File.expand_path(".") + "/", "")
      staged_path = File.join(STAGING_DIR, relative)
      
      if File.directory?(expanded)
        FileUtils.mkdir_p(staged_path)
        FileUtils.cp_r(Dir.glob("#{expanded}/**/*"), staged_path)
      else
        FileUtils.mkdir_p(File.dirname(staged_path))
        FileUtils.cp(expanded, staged_path)
      end
      
      @staged_files << { original: expanded, staged: staged_path, relative: relative }
      Result.ok(staged_path: staged_path, original: expanded)
    rescue StandardError => e
      Result.err("Failed to stage #{path}: #{e.message}")
    end
    
    # Validate staged content by running a command
    # Command is run in the staging directory context
    def validate(command: nil, &block)
      return Result.err("No files staged") if @staged_files.empty?
      
      if block_given?
        result = validate_with_block(&block)
      elsif command
        result = validate_with_command(command)
      else
        return Result.err("Must provide either command or block for validation")
      end
      
      @validation_results << result
      result
    end
    
    # Promote staged files back to original locations
    # Only if validation passed
    def promote
      return Result.err("No files staged") if @staged_files.empty?
      
      unless validation_passed?
        return Result.err("Cannot promote: validation did not pass")
      end
      
      promoted = []
      @staged_files.each do |file_info|
        FileUtils.cp(file_info[:staged], file_info[:original])
        promoted << file_info[:relative]
      end
      
      Result.ok(promoted: promoted, count: promoted.size)
    rescue StandardError => e
      Result.err("Failed to promote files: #{e.message}")
    end
    
    # Rollback and clear staging area
    def rollback
      FileUtils.rm_rf(STAGING_DIR) if File.exist?(STAGING_DIR)
      @staged_files = []
      @validation_results = []
      ensure_staging_dir
      Result.ok("Staging area cleared")
    rescue StandardError => e
      Result.err("Failed to rollback: #{e.message}")
    end
    
    # Get summary of staged files
    def summary
      {
        staged_count: @staged_files.size,
        validated: !@validation_results.empty?,
        validation_passed: validation_passed?,
        files: @staged_files.map { |f| f[:relative] }
      }
    end
    
    private
    
    def ensure_staging_dir
      FileUtils.mkdir_p(STAGING_DIR) unless File.exist?(STAGING_DIR)
    end
    
    def validation_passed?
      @validation_results.any? && @validation_results.last.ok?
    end
    
    def validate_with_command(command)
      # Run command in staging directory
      Dir.chdir(STAGING_DIR) do
        output, status = Open3.capture2e(command)
        if status.success?
          Result.ok(output: output, command: command)
        else
          Result.err("Validation failed: #{output[0..500]}")
        end
      end
    rescue StandardError => e
      Result.err("Validation command error: #{e.message}")
    end
    
    def validate_with_block
      Result.try do
        yield(STAGING_DIR, @staged_files)
      end
    rescue StandardError => e
      Result.err("Validation block error: #{e.message}")
    end
  end
end
