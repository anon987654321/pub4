# frozen_string_literal: true

require "pathname"

module Master
  module Io
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
        out = IO.popen(args, err: File::NULL, &:read)
        Result.ok(out.strip.empty? ? "(no commits)" : out.strip)
      end

      def git_blame(path)
        return Result.err("git_context blame: path required", category: :validation) unless path
        safe = safe_path(path)
        return Result.err("git_context blame: file not found: #{path}",
          category: :validation) unless File.exist?(File.join(@root, safe))
        out = IO.popen(["git", "-C", @root, "blame", "--no-color", "-l", safe], err: File::NULL, &:read)
        Result.ok(out.strip.empty? ? "(no blame data)" : out.strip)
      end

      def git_diff(path)
        args = ["git", "-C", @root, "diff", "--no-color"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL, &:read)
        Result.ok(out.strip.empty? ? "(no unstaged changes)" : out.strip)
      end

      def git_status
        out = IO.popen(["git", "-C", @root, "status", "--short", "--no-color"], err: File::NULL, &:read)
        Result.ok(out.strip.empty? ? "(clean)" : out.strip)
      end

      # `git show <rev>:<path>` prints that path's blob, so a colon in the ref turns a
      # commit viewer into a file reader — any tracked file, at any revision, including
      # ones deleted since. Every other operation here routes its path through
      # safe_path and is bounded by PathGuard; show takes no path argument at all, so
      # the colon form was the only way to ask it for one and nothing bounded it. This
      # is an LLM-callable tool (Io::LLM::GitContext), which is the difference between
      # an odd API and a way out of the root.
      #
      # Refused rather than sanitised: no caller in this tree passes <rev>:<path>, and
      # `--stat` already says this is meant to describe a commit.
      def git_show(ref)
        raw = ref.to_s.empty? ? "HEAD" : ref.to_s
        if raw.include?(":")
          return Result.err("git_context show: ref must name a commit, not <rev>:<path> — " \
                            "use blame or log for a file", category: :validation)
        end

        ref_s = raw.gsub(/[^a-zA-Z0-9._~^\-\/]/, "")
        out = IO.popen(["git", "-C", @root, "show", "--stat", "--no-color", ref_s], err: File::NULL, &:read)
        Result.ok(out.strip.empty? ? "(not found)" : out.strip[0..MAX_OUTPUT_CHARS])
      end

      def safe_path(path)
        full = File.expand_path(path.to_s, @root)
        raise "path escapes root" unless PathGuard.inside_root?(full, @root)
        Pathname.new(full).relative_path_from(@root).to_s
      end
    end
  end
end
