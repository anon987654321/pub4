# frozen_string_literal: true

require "open3"



module Master
  # GitOperations encapsulates git commands.
  # ONE_JOB: manage Git interactions for a specified repository root.
  class GitOperations
    def initialize(root_path)
      @root_path = root_path
    end

    # Reports if the target path within the repository has uncommitted changes.
    # Defaults to "lib/" if no path is specified.
    def dirty?(path = "lib/")
      Dir.chdir(@root_path) do
        out, = Open3.capture3("git status --porcelain #{path}")
        !out.strip.empty?
      end
    end

    # Stages changes for all files in "lib/".
    def add_lib_files
      Dir.chdir(@root_path) do
        system("git add -A lib/ 2>/dev/null")
      end
    end

    # Commits staged changes with the provided message.
    def commit(message)
      Dir.chdir(@root_path) do
        system("git commit -m '#{message}' 2>/dev/null")
      end
    end
  end
end