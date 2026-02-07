# frozen_string_literal: true

require 'json'
require 'fileutils'

module MASTER
  # Checkpoint system for recovering from interruptions
  class SessionRecovery
    CHECKPOINT_DIR = File.join(Paths.var, 'checkpoints')
    MAX_CHECKPOINTS = 10
    
    attr_reader :current_checkpoint
    
    def initialize
      @current_checkpoint = nil
      FileUtils.mkdir_p(CHECKPOINT_DIR)
    end
    
    # Create checkpoint
    def checkpoint(task:, files: {}, context: {}, instructions: [])
      @current_checkpoint = {
        version: 1,
        task: task,
        files: {
          completed: files[:completed] || [],
          in_progress: files[:in_progress] || [],
          pending: files[:pending] || [],
          failed: files[:failed] || []
        },
        context: {
          decisions: context[:decisions] || [],
          patterns: context[:patterns] || [],
          blockers: context[:blockers] || [],
          variables: context[:variables] || {}
        },
        recovery_instructions: instructions,
        timestamp: Time.now.to_i,
        session_id: session_id
      }
      
      save_checkpoint
      @current_checkpoint
    end
    
    # Restore from checkpoint
    def restore(checkpoint_file = nil)
      file = checkpoint_file || latest_checkpoint_file
      return nil unless file && File.exist?(file)
      
      @current_checkpoint = JSON.parse(File.read(file), symbolize_names: true)
      
      puts "Restored checkpoint from #{Time.at(@current_checkpoint[:timestamp])}"
      @current_checkpoint
    end
    
    # List available checkpoints
    def list
      Dir[File.join(CHECKPOINT_DIR, '*.json')].sort.reverse.map do |file|
        data = JSON.parse(File.read(file), symbolize_names: true)
        {
          file: File.basename(file),
          task: data[:task],
          timestamp: data[:timestamp],
          age: Time.now.to_i - data[:timestamp],
          files_pending: data.dig(:files, :pending)&.size || 0
        }
      end
    end
    
    # Get latest checkpoint
    def latest
      file = latest_checkpoint_file
      return nil unless file
      
      restore(file)
    end
    
    # Delete checkpoint
    def delete(checkpoint_file)
      file = File.join(CHECKPOINT_DIR, checkpoint_file)
      FileUtils.rm(file) if File.exist?(file)
    end
    
    # Clear all checkpoints
    def clear_all
      FileUtils.rm_rf(Dir[File.join(CHECKPOINT_DIR, '*.json')])
      @current_checkpoint = nil
    end
    
    # Update current checkpoint
    def update(updates = {})
      return nil unless @current_checkpoint
      
      # Update files status
      if updates[:files]
        updates[:files].each do |status, files|
          @current_checkpoint[:files][status] = files
        end
      end
      
      # Update context
      if updates[:context]
        updates[:context].each do |key, value|
          @current_checkpoint[:context][key] = value
        end
      end
      
      # Update instructions
      if updates[:instructions]
        @current_checkpoint[:recovery_instructions] = updates[:instructions]
      end
      
      @current_checkpoint[:timestamp] = Time.now.to_i
      save_checkpoint
    end
    
    # Mark file as completed
    def complete_file(file)
      return unless @current_checkpoint
      
      files = @current_checkpoint[:files]
      files[:pending].delete(file)
      files[:in_progress].delete(file)
      files[:completed] << file unless files[:completed].include?(file)
      
      save_checkpoint
    end
    
    # Mark file as failed
    def fail_file(file, reason: nil)
      return unless @current_checkpoint
      
      files = @current_checkpoint[:files]
      files[:pending].delete(file)
      files[:in_progress].delete(file)
      
      failure = { file: file, reason: reason, timestamp: Time.now.to_i }
      files[:failed] << failure
      
      save_checkpoint
    end
    
    # Add context decision
    def add_decision(decision)
      return unless @current_checkpoint
      
      @current_checkpoint[:context][:decisions] << {
        decision: decision,
        timestamp: Time.now.to_i
      }
      
      save_checkpoint
    end
    
    # Add blocker
    def add_blocker(blocker)
      return unless @current_checkpoint
      
      @current_checkpoint[:context][:blockers] << {
        blocker: blocker,
        timestamp: Time.now.to_i
      }
      
      save_checkpoint
    end
    
    # Get recovery instructions
    def instructions
      @current_checkpoint&.[](:recovery_instructions) || []
    end
    
    # Get pending files
    def pending_files
      @current_checkpoint&.dig(:files, :pending) || []
    end
    
    # Get progress percentage
    def progress
      return 0 unless @current_checkpoint
      
      files = @current_checkpoint[:files]
      total = files.values.flatten.size
      return 100 if total == 0
      
      completed = files[:completed].size
      (completed.to_f / total * 100).round
    end
    
    private
    
    # Save checkpoint to disk
    def save_checkpoint
      return unless @current_checkpoint
      
      filename = "checkpoint_#{@current_checkpoint[:timestamp]}.json"
      file = File.join(CHECKPOINT_DIR, filename)
      
      File.write(file, JSON.pretty_generate(@current_checkpoint))
      
      # Prune old checkpoints
      prune_checkpoints
    end
    
    # Get latest checkpoint file
    def latest_checkpoint_file
      files = Dir[File.join(CHECKPOINT_DIR, '*.json')].sort
      files.last
    end
    
    # Generate session ID
    def session_id
      @session_id ||= "session_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
    end
    
    # Remove old checkpoints
    def prune_checkpoints
      files = Dir[File.join(CHECKPOINT_DIR, '*.json')].sort
      return if files.size <= MAX_CHECKPOINTS
      
      to_delete = files.first(files.size - MAX_CHECKPOINTS)
      to_delete.each { |f| FileUtils.rm(f) }
    end
  end
end
