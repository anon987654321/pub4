# frozen_string_literal: true

# Systematic protocols - Required workflows before operations
module MASTER
  module Unified
    class Systematic
      class << self
        # Before entering directory - tree pattern
        def before_directory(path)
          return Result.err("Path does not exist: #{path}") unless Dir.exist?(path)
          
          tree_output = run_tree(path)
          
          {
            pattern: "tree",
            path: path,
            output: tree_output,
            message: "Directory structure viewed"
          }
        end

        # Before editing file - clean pattern
        def before_edit(file_path)
          return Result.err("File does not exist: #{file_path}") unless File.exist?(file_path)
          
          content = File.read(file_path)
          lines = content.lines
          size = File.size(file_path)
          
          {
            pattern: "clean",
            file: file_path,
            lines: lines.length,
            size: size,
            preview: lines.first(20).join,
            message: "File context loaded"
          }
        end

        # Before committing - diff pattern
        def before_commit
          diff_output = run_git_diff
          
          {
            pattern: "diff",
            output: diff_output,
            message: "Changes reviewed"
          }
        end

        # After error - logs pattern
        def after_error(context = {})
          logs = collect_recent_logs
          
          {
            pattern: "logs",
            logs: logs,
            context: context,
            message: "Full error context collected"
          }
        end

        # Enforce systematic protocol
        def enforce(protocol, target)
          case protocol
          when :directory
            before_directory(target)
          when :edit
            before_edit(target)
          when :commit
            before_commit
          when :error
            after_error(target)
          else
            Result.err("Unknown protocol: #{protocol}")
          end
        end

        private

        def run_tree(path)
          # Try tree command first, fall back to ls
          if command_available?("tree")
            tree_cmd = "tree -L 2 -I 'node_modules|.git' #{path}"
            result = `#{tree_cmd} 2>&1`.strip
            return result unless result.empty?
          end
          
          # Fallback to ls
          ls_cmd = "ls -la #{path}"
          `#{ls_cmd} 2>&1`.strip
        rescue StandardError => e
          "Error running tree/ls: #{e.message}"
        end

        def run_git_diff
          if Dir.exist?(".git")
            diff = `git diff 2>&1`.strip
            diff.empty? ? "No changes to commit" : diff
          else
            "Not a git repository"
          end
        rescue StandardError => e
          "Error running git diff: #{e.message}"
        end

        def collect_recent_logs
          logs = []
          
          # Check for common log files
          log_files = [
            "log/development.log",
            "log/production.log",
            "tmp/debug.log",
            "/var/log/messages"
          ]
          
          log_files.each do |file|
            next unless File.exist?(file)
            
            begin
              content = File.read(file)
              logs << {
                file: file,
                lines: content.lines.last(50)
              }
            rescue StandardError
              # Skip files we can't read
            end
          end
          
          logs
        end

        def command_available?(command)
          `which #{command} 2>&1`
          $?.success?
        rescue StandardError
          false
        end
      end
    end
  end
end
