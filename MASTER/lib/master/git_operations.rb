# frozen_string_literal: true

require "open3"

module Master
  # GitOperations — git wrappers scoped to a repository root.
  class GitOperations
    def initialize(root_path)
      @root_path = root_path
    end

    def dirty?(path = "lib/")
      out, = Open3.capture2e("git", "-C", @root_path, "status", "--porcelain", path)
      !out.strip.empty?
    end

    def add_lib_files
      Open3.capture2e("git", "-C", @root_path, "add", "-A", "lib/")
    end

    def commit(message)
      Open3.capture2e("git", "-C", @root_path, "commit", "-m", message.to_s)
    end
  end
end
