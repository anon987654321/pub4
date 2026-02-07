# frozen_string_literal: true

require 'fileutils'
require 'open3'

module MASTER
  # Staging - Safe self-refactor with validation and rollback
  # Copies files to staging area, validates changes, promotes on success
  class Staging
    attr_reader :staging_dir, :backups
    
    def initialize(staging_dir: nil)
      @staging_dir = staging_dir || File.join(Paths.var, "staging")
      @backups = {}
      FileUtils.mkdir_p(@staging_dir)
    end
    
    # Stage a file for modification
    # Returns: { staged_path: String, original_path: String }
    def stage_file(path)
      expanded = File.expand_path(path)
      return Result.err("File not found: #{path}") unless File.exist?(expanded)
      
      # Create backup
      backup_path = create_backup(expanded)
      @backups[expanded] = backup_path
      
      # Copy to staging
      relative = relative_path(expanded)
      staged_path = File.join(@staging_dir, relative)
      FileUtils.mkdir_p(File.dirname(staged_path))
      FileUtils.cp(expanded, staged_path)
      
      Result.ok(staged_path: staged_path, original_path: expanded)
    end
    
    # Validate staged changes
    # Runs validation commands from constitution
    def validate(staged_path)
      const = load_constitution
      validation_cmds = const.dig("staging", "validation_commands") || []
      
      # Default validations if none specified
      validation_cmds = ["ruby -c {file}"] if validation_cmds.empty?
      
      results = []
      validation_cmds.each do |cmd_template|
        cmd = cmd_template.gsub("{file}", staged_path)
        stdout, stderr, status = Open3.capture3(cmd)
        
        results << {
          command: cmd,
          success: status.success?,
          stdout: stdout,
          stderr: stderr
        }
        
        # Stop on first failure
        unless status.success?
          return Result.err("Validation failed: #{cmd}\n#{stderr}")
        end
      end
      
      Result.ok(results: results)
    end
    
    # Promote staged file to original location
    def promote(staged_path, original_path)
      return Result.err("Staged file not found") unless File.exist?(staged_path)
      return Result.err("Original path not in backups") unless @backups[original_path]
      
      begin
        FileUtils.cp(staged_path, original_path)
        Result.ok(promoted: original_path)
      rescue => e
        Result.err("Failed to promote: #{e.message}")
      end
    end
    
    # Rollback to backup
    def rollback(original_path)
      backup_path = @backups[original_path]
      return Result.err("No backup found for #{original_path}") unless backup_path
      return Result.err("Backup not found: #{backup_path}") unless File.exist?(backup_path)
      
      begin
        FileUtils.cp(backup_path, original_path)
        Result.ok(rolled_back: original_path)
      rescue => e
        Result.err("Failed to rollback: #{e.message}")
      end
    end
    
    # Full workflow: stage, modify, validate, promote
    def staged_modify(path, &block)
      # Stage the file
      stage_result = stage_file(path)
      return stage_result unless stage_result.ok?
      
      staged_path = stage_result.value[:staged_path]
      original_path = stage_result.value[:original_path]
      
      # Allow caller to modify staged file
      begin
        yield(staged_path)
      rescue => e
        rollback(original_path)
        return Result.err("Modification failed: #{e.message}")
      end
      
      # Validate changes
      validation = validate(staged_path)
      unless validation.ok?
        rollback(original_path)
        return validation
      end
      
      # Promote to original location
      promote_result = promote(staged_path, original_path)
      unless promote_result.ok?
        rollback(original_path)
        return promote_result
      end
      
      Result.ok(
        path: original_path,
        validated: true,
        promoted: true
      )
    end
    
    # Clean up staging directory
    def cleanup
      FileUtils.rm_rf(@staging_dir) if File.exist?(@staging_dir)
      @backups.clear
      Result.ok(cleaned: true)
    end
    
    private
    
    def create_backup(path)
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      backup_dir = File.join(Paths.var, "backups")
      FileUtils.mkdir_p(backup_dir)
      
      basename = File.basename(path)
      backup_path = File.join(backup_dir, "#{basename}.#{timestamp}")
      
      FileUtils.cp(path, backup_path)
      backup_path
    end
    
    def relative_path(absolute_path)
      root = MASTER.root
      absolute_path.sub(/^#{Regexp.escape(root)}\//, "")
    end
    
    def load_constitution
      const_file = File.join(Paths.data, "constitution.yml")
      File.exist?(const_file) ? YAML.safe_load_file(const_file) : {}
    rescue => e
      warn "Failed to load constitution: #{e.message}"
      {}
    end
  end
end
