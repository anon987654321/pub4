# frozen_string_literal: true

require "open3"
require "timeout"

module Master
  module Fix
    class FixLoop
      # Commits what one fix-loop pass changed, and only that.
      #
      # The checkout is shared by several sessions and a human, so a path that
      # was already modified or untracked when the pass began is someone else's
      # work in progress. baseline! records those paths at the start of a pass;
      # commit_if_dirty commits the paths that changed since, path-scoped, and
      # never the index. With no baseline nothing is known to be the pass's own,
      # so nothing is committed.
      class Committer
        LINT_TIMEOUT_SECONDS = 20
        FINDING_LINES = 40

        def initialize(git:, bus: nil, root: nil, ground_truth: nil, preserve_user_intent: nil)
          @git = git
          @bus = bus
          @root = root
          @ground_truth = ground_truth
          @preserve_user_intent = preserve_user_intent
          @baseline = nil
        end

        def baseline!
          @baseline = @git.changed_paths
        rescue StandardError => e
          @baseline = nil
          @bus&.publish("fix_loop:commit_error", error: e.message)
        end

        # findings are the violations the pass set out to fix; the ones in a
        # committed file are named in the body, so git log says which rule each
        # runtime commit answered.
        def commit_if_dirty(message, findings: [])
          paths = own_changes
          return if paths.empty?

          broken = ruby_files(paths).reject { |path| ruby_parses?(path) }
          return block_commit(broken) unless broken.empty?
          return block_commit_intent(message) unless intent_preserved?(message, paths)
          return block_commit_ground_truth unless ground_truth_fresh?(paths)
          return unless lint_changed_ruby(paths)

          @git.commit(with_finding_ids(message, findings, paths), paths:)
          @bus&.publish("ops:commit", message: message.to_s[0, 120], head: @git.head, paths:)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error: e.message)
        end

        private

        def with_finding_ids(message, findings, paths)
          lines = Array(findings).filter_map do |finding|
            file = finding[:file].to_s.delete_prefix("#{@root}/")
            "#{finding[:rule]} #{file}:#{finding[:line].to_i}" if paths.include?(file)
          end.uniq
          return message.to_s if lines.empty?

          extra = lines.size > FINDING_LINES ? ["and #{lines.size - FINDING_LINES} more"] : []
          [message.to_s, "", *lines.first(FINDING_LINES), *extra].join("\n")
        end

        def own_changes
          return [] unless @baseline

          @git.changed_paths - @baseline
        end

        def block_commit(files)
          @bus&.publish("fix_loop:commit_blocked", reason: "syntax", files:)
          nil
        end

        def block_commit_intent(message)
          @bus&.publish("fix_loop:commit_blocked", reason: "preserve_user_intent", message: message.to_s[0, 120])
          nil
        end

        def block_commit_ground_truth
          @bus&.publish("fix_loop:commit_blocked", reason: "ground_truth")
          nil
        end

        def intent_preserved?(message, paths)
          return true unless @preserve_user_intent && @root

          result = @preserve_user_intent.assert_preserved!(git_diff(paths), message:)
          result.ok?
        end

        def ground_truth_fresh?(paths)
          return true unless @ground_truth && @root

          stale = ruby_files(paths).reject { |path| @ground_truth.fresh?(path) }
          return true if stale.empty?

          stale.each { |path| @ground_truth.assert_fresh!(path, reason: "commit_creation") }
          false
        end

        def git_diff(paths)
          out, = Master::Io::Exec.capture2e("git", "-C", @root, "diff", "HEAD", "--", *paths)
          out.to_s
        rescue StandardError
          ""
        end

        def lint_changed_ruby(paths)
          files = ruby_files(paths)
          return true if files.empty?
          return skip_lint("missing Gemfile") unless bundle_context?

          cmd = [Master::BUNDLE_BIN, "exec", "rubocop", "--fail-level", "E", "--force-exclusion", *files]
          _out, _err, status = Timeout.timeout(LINT_TIMEOUT_SECONDS) { Master::Io::Exec.capture3(*cmd, chdir: @root) }
          if status.success?
            true
          else
            @bus&.publish("fix_loop:commit_blocked", reason: "rubocop", files:)
            false
          end
        rescue Timeout::Error
          skip_lint("rubocop timed out after #{LINT_TIMEOUT_SECONDS}s")
        rescue Errno::ENOENT, StandardError => e
          skip_lint(e.message)
        end

        def skip_lint(error)
          @bus&.publish("fix_loop:commit_lint_skipped", error:)
          true
        end

        def bundle_context?
          @root && File.file?(File.join(@root, "Gemfile"))
        end

        # Absolute paths of the Ruby files among the pass's own changes.
        def ruby_files(paths)
          return [] unless @root

          paths.select { |path| path.end_with?(".rb") }.map { |path| File.join(@root, path) }
        end

        def ruby_parses?(absolute_path)
          return true unless File.file?(absolute_path)

          RubyVM::InstructionSequence.compile(File.read(absolute_path))
          true
        rescue SyntaxError => e
          Master::Ground::Swallow.log(e, context: "Committer.ruby_parses?")
          false
        end
      end
    end
  end
end
