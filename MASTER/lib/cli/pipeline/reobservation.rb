# frozen_string_literal: true

module Master
  module CLI
    class Pipeline

      # What the second reading of a repair has to read again. A repair rewrites a few files, so the
      # second reading covers the files that differ from the pre-repair commit and carries the first
      # reading's counts for the rest. A change to a law, the scanner or a config moves what every
      # other file reports, so those repairs, and a repair of too many files, get the whole tree.
      class Reobservation
        LIMIT = 200
        WHOLE_TREE = %r{
          \A(?:MASTER/)?(?:law/|lib/(?:review|fix/scan|cli/scan)/|data/[^/]+\.yml\z)|(?:\A|/)\.(?:rubocop|reek)
        }x

        Scope = Struct.new(:changed, :files)

        def initialize(git:, root:, first_total:, first_counts:)
          @git = git
          @root = root
          @first_total = first_total
          @first_counts = first_counts
        end

        # The changed files inside target, or nil when only a whole-tree reading will do.
        def scope(before, target)
          return if before.nil? || ENV["MASTER_FIX_FULL_REOBSERVE"] == "1"

          paths = @git.paths_since(before)
          return if paths.nil? || paths.any? { |path| path.match?(WHOLE_TREE) }

          changed = readable(paths, target)
          Scope.new(changed, changed.select { |path| File.file?(path) }) if changed.size <= LIMIT
        end

        # The first total, less what the changed files held then, plus what they hold now.
        def total(changed, counts_now)
          @first_total - @first_counts.values_at(*changed).compact.sum + counts_now.values.sum
        end

        private

        def readable(paths, target)
          absolute = paths.map { |path| File.expand_path(path, Master::REPO_ROOT) }
          absolute.select! { |path| within?(path, target) }
          absolute.reject { |path| Master::Fix::Scanner.skip_path?(path, root: @root) }
        end

        def within?(path, target)
          base = target.to_s.chomp("/")
          path == base || path.start_with?("#{base}/")
        end
      end
    end
  end
end
