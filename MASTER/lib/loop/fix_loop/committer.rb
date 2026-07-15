# frozen_string_literal: true

require "open3"
require "timeout"

module Master
  module Loop
    class FixLoop
      class Committer
        LINT_TIMEOUT_SECONDS = 20

        def initialize(git:, bus: nil, root: nil, ground_truth: nil, preserve_user_intent: nil)
          @git = git
          @bus = bus
          @root = root
          @ground_truth = ground_truth
          @preserve_user_intent = preserve_user_intent
        end

        def commit_if_dirty(message)
          return unless @git&.dirty?(".")

          broken = unparseable_changed_ruby
          return block_commit(broken) unless broken.empty?
          return block_commit_intent(message) unless intent_preserved?(message)
          return block_commit_ground_truth unless ground_truth_fresh?
          return unless lint_changed_ruby

          @git.add_all
          @git.commit(message)
          @bus&.publish("ops:commit", message: message.to_s[0, 120], head: @git.head)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error: e.message)
        end

        private

        # Never commit a tree where an autofix left Ruby unparseable (the corruption guard).
        def unparseable_changed_ruby
          return [] unless @root

          @git.status_lines(".").filter_map { |line| changed_ruby_path(line) }.reject { |path| ruby_parses?(path) }
        end

        def block_commit(files)
          @bus&.publish("fix_loop:commit_blocked", reason: "syntax", files: files)
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

        def intent_preserved?(message)
          return true unless @preserve_user_intent && @root

          diff = git_diff
          result = @preserve_user_intent.assert_preserved!(diff, message:)
          result.ok?
        end

        def ground_truth_fresh?
          return true unless @ground_truth && @root

          stale = changed_ruby_files.reject { |path| @ground_truth.fresh?(path) }
          return true if stale.empty?

          stale.each { |path| @ground_truth.assert_fresh!(path, reason: "commit_creation") }
          false
        end

        def git_diff
          out, = Master::Reach::Exec.capture2e("git", "-C", @root, "diff", "HEAD")
          out.to_s
        rescue StandardError
          ""
        end

        def lint_changed_ruby
          files = changed_ruby_files
          return true if files.empty?
          return skip_lint("missing Gemfile") unless bundle_context?

          cmd = [Master::BUNDLE_BIN, "exec", "rubocop", "--fail-level", "E", "--force-exclusion", *files]
          _out, _err, status = Timeout.timeout(LINT_TIMEOUT_SECONDS) { Master::Reach::Exec.capture3(*cmd, chdir: @root) }
          if status.success?
            true
          else
            @bus&.publish("fix_loop:commit_blocked", reason: "rubocop", files: files)
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

        def changed_ruby_files
          return [] unless @root

          @git.status_lines(".").filter_map { |line| changed_ruby_path(line) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Committer.changed_ruby_files")
          []
        end

        def changed_ruby_path(status_line)
          rel = status_line[3..].to_s.strip
          return if rel.empty? || !rel.end_with?(".rb")

          File.join(@root, rel)
        end

        def ruby_parses?(absolute_path)
          return true unless File.file?(absolute_path)

          RubyVM::InstructionSequence.compile(File.read(absolute_path))
          true
        rescue SyntaxError
          false
        end
      end
    end
  end
end
