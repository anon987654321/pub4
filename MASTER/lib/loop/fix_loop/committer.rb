# frozen_string_literal: true

module Master
  module Loop
    class FixLoop
      class Committer
        def initialize(git:, bus: nil, root: nil)
          @git = git
          @bus = bus
          @root = root
        end

        def commit_if_dirty(message)
          return unless @git&.dirty?(".")

          broken = unparseable_changed_ruby
          return block_commit(broken) unless broken.empty?
          return unless lint_changed_ruby

          @git.add_all
          @git.commit(message)
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

        def lint_changed_ruby
          files = changed_ruby_files
          return true if files.empty?

          cmd = [Master::BUNDLE_BIN, "exec", "rubocop", "--fail-level", "E", "--force-exclusion", *files]
          _out, _err, status = Open3.capture3(*cmd, chdir: @root)
          if status.success?
            true
          else
            @bus&.publish("fix_loop:commit_blocked", reason: "rubocop", files: files)
            false
          end
        rescue Errno::ENOENT, StandardError => e
          @bus&.publish("fix_loop:commit_lint_skipped", error: e.message)
          true
        end

        def changed_ruby_files
          return [] unless @root

          @git.status_lines(".").filter_map { |line| changed_ruby_path(line) }
        rescue StandardError
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
