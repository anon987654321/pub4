# frozen_string_literal: true

module Master
  module Io
    class GitOperations
      # State-changing git commands (add/commit/push/reset/tag/fetch) — kept
      # separate from GitOperations' own read-only status/inspection queries.
      module Mutations
        def add_all
          Master::Io::Exec.capture2e("git", "-C", @root_path, "add", "-A")
        end

        def commit(message)
          Master::Io::Exec.capture2e("git", "-C", @root_path, "commit", "-m", message.to_s)
        end

        def push
          Master::Io::Exec.capture2e("git", "-C", @root_path, "push")
        end

        def reset_hard(ref = "origin/main")
          Master::Io::Exec.capture2e("git", "-C", @root_path, "reset", "--hard", ref)
        end

        def tag(name)
          Master::Io::Exec.capture2e("git", "-C", @root_path, "tag", name)
        end

        def fetch
          Master::Io::Exec.capture2e("git", "-C", @root_path, "fetch")
        end
      end
    end
  end
end
