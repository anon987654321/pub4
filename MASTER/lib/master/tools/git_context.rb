# frozen_string_literal: true

module Master
  module Tools
    # Git context tool — query history, blame, diff, and status.
    # All commands are read-only (TIER :safe). No writes.
    class GitContext
      TIER        = :safe
      NAME        = "git_context".freeze
      DESCRIPTION = "Query git log, blame, diff, and status for the project.".freeze

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(operation:, path: nil, limit: 20)
        Dir.chdir(@root) do
          case operation.to_s
          when "log"    then git_log(path, limit.to_i)
          when "blame"  then git_blame(path)
          when "diff"   then git_diff(path)
          when "status" then git_status
          when "show"   then git_show(path)
          else
            Result.err("git_context: unknown operation: #{operation}", category: :validation)
          end
        end
      rescue => e
        Result.err("git_context: #{e.message}", category: :unknown)
      end

      private

      def git_log(path, limit)
        args = ["git", "log", "--oneline", "--no-color", "-#{limit}"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no commits)" : out.strip)
      end

      def git_blame(path)
        return Result.err("git_context blame: path required", category: :validation) unless path
        safe = safe_path(path)
        return Result.err("git_context blame: file not found: #{path}", category: :validation) unless File.exist?(File.join(@root, safe))
        out = IO.popen(["git", "blame", "--no-color", "-l", safe], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no blame data)" : out.strip)
      end

      def git_diff(path)
        args = ["git", "diff", "--no-color"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no unstaged changes)" : out.strip)
      end

      def git_status
        out = IO.popen(["git", "status", "--short", "--no-color"], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(clean)" : out.strip)
      end

      def git_show(ref)
        ref_s = (ref.to_s.empty? ? "HEAD" : ref.to_s).gsub(/[^a-zA-Z0-9._~^:\-\/]/, "")
        out = IO.popen(["git", "show", "--stat", "--no-color", ref_s], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(not found)" : out.strip[0..4000])
      end

      # Prevent path traversal: resolve relative to root, must stay inside
      def safe_path(path)
        full = File.expand_path(path.to_s, @root)
        raise "path escapes root" unless full.start_with?(@root)
        Pathname.new(full).relative_path_from(@root).to_s
      end
    end
  end
end
