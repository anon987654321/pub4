# frozen_string_literal: true

require "pathname"

module Master
  module Fix
    class FixLoop

      # /fix runs from MASTER's directory, and its git sees only MASTER: a repair to a RAILS or
      # OPENBSD file was applied, counted, and never committed. The committer also asks the
      # repository root for changes beside MASTER, names them relative to MASTER (../RAILS/...),
      # and commits through the repository root whenever a commit holds one.
      module RepoScope
        def changed_everywhere
          inside = Array(@git.changed_paths)
          return inside unless repo_git

          own = "#{repo_prefix}/"
          inside + Array(repo_git.changed_paths).reject { |path| path.start_with?(own) }.map { |path| "../#{path}" }
        end

        def commit_scoped(message, paths:)
          @lease_guard&.call
          return @git.commit(message, paths:) unless repo_git && paths.any? { |path| path.start_with?("../") }

          repo_git.commit(message, paths: paths.map { |path| repo_relative(path) })
        end

        private

        def repo_root = Master::REPO_ROOT

        def repo_git
          return @repo_git if defined?(@repo_git)

          @repo_git = beside_repo? ? Master::Io::GitOperations.new(repo_root) : nil
        end

        def beside_repo? = @root && File.expand_path(@root).start_with?("#{File.expand_path(repo_root)}/")

        def repo_prefix = Pathname.new(File.expand_path(@root)).relative_path_from(File.expand_path(repo_root)).to_s

        def repo_relative(path)
          Pathname.new(File.expand_path(path, @root)).relative_path_from(File.expand_path(repo_root)).to_s
        end
      end
    end
  end
end
