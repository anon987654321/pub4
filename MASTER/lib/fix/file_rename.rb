# frozen_string_literal: true

require "open3"
require "prism"
require_relative "../operator/readers"

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


      module References
        SASS_LOAD = /(@(?:use|forward|import)\s+["'](?:[^"']*\/)?)%<name>s(["'])/

        def self.forms(from, to)
          old_base = File.basename(from)
          new_base = File.basename(to)
          old_stem = old_base.sub(/\..*\z/, "")
          new_stem = new_base.sub(/\..*\z/, "")
          pairs = [[old_base, new_base], [old_stem, new_stem]]
          pairs << [old_stem.delete_prefix("_"), new_stem.delete_prefix("_")] if old_stem.start_with?("_")
          pairs.uniq
        end

        def self.rewrite(text, from, to)
          out = text.dup
          forms(from, to).each do |old, new|
            if old.start_with?("_") || old.include?(".")
              out.gsub!(/(?<![\w-])#{Regexp.escape(old)}(?![\w-])/, new)
            else
              out.gsub!(Regexp.new(format(SASS_LOAD.source, name: Regexp.escape(old)))) { "#{$1}#{new}#{$2}" }
            end
          end
          out == text ? nil : out
        end

        def self.remaining(root, from, to)
          each_file(root).select do |path|
            text = File.read(path, encoding: "UTF-8")
            text.valid_encoding? && !rewrite(text, from, to).nil?
          rescue ArgumentError
            false
          end
        end

        def self.each_file(root)
          Operator::Readers::TREES.flat_map do |tree|
            Dir.glob(File.join(root, tree, "**", "*")).reject do |path|
              path.match?(Operator::Readers::SKIP) || path.include?("/builds/") || !File.file?(path) ||
                File.size(path) > 2_000_000
            end
          end
        end
      end

      module CssBuild
        APPS = %w[amber brgen bsdports].freeze
        SASS = "sass@1.93.2"

        def self.rules(repo_root)
          rails = File.join(repo_root, "RAILS")
          APPS.to_h do |app|
            out, err, status = Open3.capture3("npx", "--yes", SASS, "--no-source-map", "--quiet",
                                              "--load-path=#{app}/app/assets/stylesheets",
                                              "--load-path=shared/app/assets/stylesheets",
                                              "#{app}/app/assets/stylesheets/application.scss", chdir: rails)
            raise "sass failed for #{app}: #{err.lines.first(3).join}" unless status.success?

            [app, out.gsub(%r{/\*.*?\*/}m, "")]
          end
        end
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
