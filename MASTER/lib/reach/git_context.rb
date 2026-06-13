# frozen_string_literal: true

module Master
  module Reach
    class GitContext
      TIER = :safe
      NAME = "git_context".freeze
      DESCRIPTION = "Query git log, blame, diff, and status for the project.".freeze
      MAX_OUTPUT_CHARS = 4000

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus = event_bus
      end

      def call(operation:, path: nil, limit: 20)
        case operation.to_s
        when "log" then git_log(path, limit.to_i)
        when "blame" then git_blame(path)
        when "diff" then git_diff(path)
        when "status" then git_status
        when "show"   then git_show(path)
        else
          Result.err("git_context: unknown operation: #{operation}", category: :validation)
        end
      rescue StandardError => e
        Result.err("git_context: #{e.message}", category: :unknown)
      end

      private

      def git_log(path, limit)
        args = ["git", "-C", @root, "log", "--oneline", "--no-color", "-#{limit}"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no commits)" : out.strip)
      end

      def git_blame(path)
        return Result.err("git_context blame: path required", category: :validation) unless path
        return Result.err("git_context blame: file not found: #{path}",
        out = IO.popen(["git", "-C", @root, "blame", "--no-color", "-l", safe], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no blame data)" : out.strip)
      end

      def git_diff(path)
        args = ["git", "-C", @root, "diff", "--no-color"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no unstaged changes)" : out.strip)
      end

      def git_status
        out = IO.popen(["git", "-C", @root, "status", "--short", "--no-color"], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(clean)" : out.strip)
      end

      def git_show(ref)
        ref_s = (ref.to_s.empty? ? "HEAD" : ref.to_s).gsub(/[^a-zA-Z0-9._~^:\-\/]/, "")
        out = IO.popen(["git", "-C", @root, "show", "--stat", "--no-color", ref_s], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(not found)" : out.strip[0..MAX_OUTPUT_CHARS])
      end

      def safe_path(path)
        full = File.expand_path(path.to_s, @root)
        raise "path escapes root" unless full.start_with?(@root)
      end
    end
  end
end
