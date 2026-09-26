# frozen_string_literal: true

require "prism"
require_relative "file_rename/references"
require_relative "file_rename/css_build"

module Master
  module Fix
    # Moves one file to a better name, rewrites every reference to it across the
    # three governed trees, and keeps the move only if it can be proved harmless; otherwise
    # it puts everything back. One commit per rename, so a bad name is one revert.
    #
    # The kinds it renames are the ones whose name nothing but a path reaches:
    # Sass partials and Markdown documents. A Ruby file's name is its constant
    # under Zeitwerk and a Rails partial's is its render call, and those need a
    # different proof, so they are not renamed here.
    class FileRename
      KINDS = {
        stylesheet: %r{/stylesheets/_[^/]+\.scss\z},
        document: %r{\.md\z},
      }.freeze
      # A convention file is found by its name; renaming it loses it.
      FIXED_NAMES = %w[README.md CLAUDE.md AGENTS.md GEMINI.md TODO.md TREE.md CHANGELOG.md LICENSE.md].freeze

      def self.kind(path)
        return if FIXED_NAMES.include?(File.basename(path)) || path.match?(%r{/(vendor|node_modules|builds)/})

        KINDS.find { |_, pattern| path.match?(pattern) }&.first
      end

      def initialize(repo_root:, git: nil, css_rules: ->(root) { CssBuild.rules(root) })
        @root = repo_root
        @git = git || Io::GitOperations.new(repo_root)
        @css_rules = css_rules
      end

      # from is repository-relative; to_basename is the new file name alone.
      def call(from, to_basename, reason:)
        to = File.join(File.dirname(from), to_basename)
        kind = self.class.kind(from)
        return Result.err("rename: #{from} is not a kind FileRename can prove", category: :policy) unless kind
        return Result.err("rename: #{from} or its readers have uncommitted changes", category: :policy) unless clean?(from, to)

        before = kind == :stylesheet ? @css_rules.call(@root) : nil
        edited = move_and_rewrite(from, to)
        failure = proof_failure(kind:, from:, to:, before:, edited:)
        return undo(from, to, edited, failure) if failure

        commit(from, to, edited, reason)
      end

      private

      def clean?(from, to)
        return false if File.exist?(File.join(@root, to))

        readers = References.each_file(@root).select { |path| References.rewrite(read(path), from, to) }
        paths = [from, *readers.map { |path| relative(path) }]
        @git.status_lines(nil).none? { |line| paths.include?(line[3..].to_s.strip) }
      end

      def move_and_rewrite(from, to)
        @git.git!("mv", "--", from, to)
        References.each_file(@root).filter_map do |path|
          rewritten = References.rewrite(read(path), from, to)
          next unless rewritten

          File.write(path, rewritten)
          relative(path)
        end
      end

      def proof_failure(kind:, from:, to:, before:, edited:)
        left = References.remaining(@root, from, to)
        return "still named at #{left.first(3).map { |path| relative(path) }.join(", ")}" unless left.empty?

        broken = edited.select { |path| path.end_with?(".rb") && Prism.parse_file(File.join(@root, path)).failure? }
        return "Ruby no longer parses in #{broken.join(", ")}" unless broken.empty?
        return unless kind == :stylesheet

        after = @css_rules.call(@root)
        changed = before.keys.reject { |app| before[app] == after[app] }
        "compiled CSS changed for #{changed.join(", ")}" unless changed.empty?
      rescue StandardError => e
        "proof could not run: #{e.message}"
      end

      def undo(from, to, edited, failure)
        @git.git!("reset", "-q", "--", from, to, *edited)
        @git.git!("checkout", "--", from, *edited)
        target = File.join(@root, to)
        File.delete(target) if File.exist?(target)
        Result.err("rename #{from} -> #{File.basename(to)} undone: #{failure}", category: :validation)
      end

      def commit(from, to, edited, reason)
        message = "refactor: #{from} is #{File.basename(to)}\n\n#{reason}\n\n" \
                  "Renamed by /fix; #{edited.size} reference(s) rewritten, proof held."
        # Not GitOperations#commit: it `git add`s every path, and the old one
        # no longer exists; git mv has already staged its removal.
        @git.git!("add", "--", to, *edited)
        @git.git!("commit", "-m", message, "-m", Master::Core::World::COMMIT_TRAILER, "--", from, to, *edited)
        Result.ok(from:, to:, references: edited.size)
      end

      def read(path) = File.read(path, encoding: "UTF-8").then { |text| text.valid_encoding? ? text : "" }
      def relative(path) = path.delete_prefix("#{@root}/")
    end
  end
end
