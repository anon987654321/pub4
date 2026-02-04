# frozen_string_literal: true
require "json"
require "fileutils"
require "time"
require "find"

module Master
  module Memory
    class GitBacked
      MEMORY_DIR = ".master_memory"
      MEMORY_BRANCH = "master-memory"
      
      attr_reader :memory_path
      
      def initialize(root_path = nil)
        @root_path = root_path || Dir.pwd
        @memory_path = File.join(@root_path, MEMORY_DIR)
        @git_available = check_git_available
        ensure_memory_dir
      end
      
      # Record a decision (violation found, fix applied, etc.)
      def record_decision(file, violation, decision, context = {})
        return unless @git_available
        
        entry = {
          timestamp: Time.now.utc.iso8601,
          event_type: decision[:type] || "violation_found",
          file: file,
          violation: violation,
          decision: decision[:action] || "unknown",
          cost: decision[:cost] || 0.0,
          context: context
        }
        
        save_entry(entry)
        commit_entry(entry) if @git_available
        entry
      end
      
      # Search for similar violations in history
      def search_similar_violations(violation, limit: 10)
        return [] unless Dir.exist?(@memory_path)
        
        results = []
        pattern = violation[:principle] || violation["principle"]
        
        Find.find(@memory_path) do |path|
          next unless path.end_with?(".json")
          next if File.directory?(path)
          
          begin
            entry = JSON.parse(File.read(path))
            if matches_violation?(entry, pattern)
              results << entry
            end
          rescue JSON::ParserError, Errno::ENOENT
            # Skip invalid files
          end
        end
        
        results.sort_by { |e| e["timestamp"] }.reverse.take(limit)
      end
      
      # Get user patterns (what they typically fix vs ignore)
      def get_user_patterns
        return {} unless Dir.exist?(@memory_path)
        
        patterns = Hash.new { |h, k| h[k] = { fixed: 0, ignored: 0, deferred: 0 } }
        
        Find.find(@memory_path) do |path|
          next unless path.end_with?(".json")
          next if File.directory?(path)
          
          begin
            entry = JSON.parse(File.read(path))
            principle = entry.dig("violation", "principle")
            decision = entry["decision"]
            
            if principle && decision
              patterns[principle][decision.to_sym] += 1
            end
          rescue JSON::ParserError, Errno::ENOENT
            # Skip invalid files
          end
        end
        
        patterns
      end
      
      # Get all past decisions for a specific file
      def get_file_history(file)
        return [] unless Dir.exist?(@memory_path)
        
        results = []
        
        Find.find(@memory_path) do |path|
          next unless path.end_with?(".json")
          next if File.directory?(path)
          
          begin
            entry = JSON.parse(File.read(path))
            if entry["file"] == file
              results << entry
            end
          rescue JSON::ParserError, Errno::ENOENT
            # Skip invalid files
          end
        end
        
        results.sort_by { |e| e["timestamp"] }
      end
      
      # Sync memory with remote repository
      def sync_with_remote(remote: "origin")
        return false unless @git_available
        
        begin
          # Try to push memory branch to remote
          `cd #{@root_path} && git push #{remote} #{MEMORY_BRANCH} 2>&1`
          $?.success?
        rescue => e
          warn "Memory sync failed: #{e.message}"
          false
        end
      end
      
      private
      
      def check_git_available
        system("git --version > /dev/null 2>&1")
      end
      
      def ensure_memory_dir
        FileUtils.mkdir_p(@memory_path) unless Dir.exist?(@memory_path)
      rescue Errno::EACCES
        # Can't create directory (sandbox restriction)
        @git_available = false
      end
      
      def save_entry(entry)
        timestamp = Time.parse(entry[:timestamp])
        year = timestamp.strftime("%Y")
        month = timestamp.strftime("%m")
        day = timestamp.strftime("%d")
        time_str = timestamp.strftime("%H-%M-%S")
        
        dir_path = File.join(@memory_path, year, month, day)
        FileUtils.mkdir_p(dir_path)
        
        # Generate filename from event type and file
        file_basename = File.basename(entry[:file] || "unknown", ".*").gsub(/[^a-zA-Z0-9_-]/, "_")
        filename = "#{time_str}_#{entry[:event_type]}_#{file_basename}.json"
        file_path = File.join(dir_path, filename)
        
        File.write(file_path, JSON.pretty_generate(entry))
        file_path
      end
      
      def commit_entry(entry)
        return unless @git_available
        
        Dir.chdir(@root_path) do
          # Check if we're in a git repo
          return unless system("git rev-parse --git-dir > /dev/null 2>&1")
          
          # Create/checkout memory branch
          unless branch_exists?(MEMORY_BRANCH)
            system("git checkout --orphan #{MEMORY_BRANCH} > /dev/null 2>&1")
            system("git rm -rf . > /dev/null 2>&1")
            system("git checkout main -- #{MEMORY_DIR} > /dev/null 2>&1")
          end
          
          # Add and commit
          system("git add #{MEMORY_DIR} > /dev/null 2>&1")
          msg = "Memory: #{entry[:event_type]} in #{File.basename(entry[:file] || 'unknown')}"
          system("git commit -m '#{msg}' > /dev/null 2>&1")
          
          # Return to previous branch
          system("git checkout - > /dev/null 2>&1")
        end
      rescue => e
        # Silently fail on git operations
      end
      
      def branch_exists?(branch)
        `git branch --list #{branch}`.strip != ""
      end
      
      def matches_violation?(entry, pattern)
        return false unless entry["violation"]
        
        principle = entry.dig("violation", "principle")
        description = entry.dig("violation", "description")
        
        return true if principle && principle.include?(pattern)
        return true if description && description.include?(pattern)
        
        false
      end
    end
  end
end
