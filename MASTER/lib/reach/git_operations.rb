# frozen_string_literal: true

require "open3"

module Master
  module Reach
  # GitOperations — git wrappers scoped to a repository root.
  class GitOperations
    def initialize(root_path)
      @root_path = root_path
    end

    def dirty?(path = "lib/")
      out, = Open3.capture2e("git", "-C", @root_path, "status", "--porcelain", path)
      !out.strip.empty?
    end

    def add_all
      Open3.capture2e("git", "-C", @root_path, "add", "-A")
    end

    def commit(message)
      Open3.capture2e("git", "-C", @root_path, "commit", "-m", message.to_s)
    end

    def push
      Open3.capture2e("git", "-C", @root_path, "push")
    end

    def ahead_behind
      out, _, st = Open3.capture3(
        "git", "-C", @root_path, "rev-list", "--left-right", "--count", "HEAD...@{u}"
      )
      return [0, 0] unless st.success?
      a, b = out.strip.split.map(&:to_i)
      [a || 0, b || 0]
    end

    def diff_stat(base = "HEAD")
      out, = Open3.capture2e("git", "-C", @root_path, "diff", base, "--stat")
      out.strip
    end

    def reset_hard(ref = "origin/main")
      Open3.capture2e("git", "-C", @root_path, "reset", "--hard", ref)
    end

    def tag(name)
      Open3.capture2e("git", "-C", @root_path, "tag", name)
    end

    def fetch
      Open3.capture2e("git", "-C", @root_path, "fetch")
    end

    def head
      out, _, st = Open3.capture3("git", "-C", @root_path, "rev-parse", "--short", "HEAD")
      st.success? ? out.strip : nil
    end

    def branch
      out, _, st = Open3.capture3("git", "-C", @root_path, "rev-parse", "--abbrev-ref", "HEAD")
      st.success? ? out.strip : nil
    end
  end
  end
end
