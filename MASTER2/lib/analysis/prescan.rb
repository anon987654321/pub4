# frozen_string_literal: true
require "shellwords"
require "digest"

module MASTER
  module Analysis
    # Prescan - Mandatory situational awareness before touching code
    # Ported from MASTER v1 cli.rb prescan ritual
    module Prescan
      extend self
      TREE_EXCLUDES = %w[. .. .git vendor tmp node_modules var].freeze

      def run(path = MASTER.root, tree_depth: 4, cache: false)
        path = File.expand_path(path)
        @cache ||= {}
        if cache && @cache.key?(path)
          return @cache[path]
        end

        tree_lines = project_tree(path, max_depth: tree_depth)
        results = {
          tree: tree_lines,
          tree_digest: Digest::SHA256.hexdigest(tree_lines.join("\n")),
          tree_nodes: tree_lines.size,
          sprawl: detect_sprawl(path),
          git_status: check_git_status(path),
          recent_commits: recent_commits(path),
        }

        warn_if_issues(results)
        @cache[path] = results if cache
        results
      end

      private

      def project_tree(path, max_depth: 4)
        lines = file_tree(path, max_depth: max_depth, exclude: TREE_EXCLUDES)
        puts UI.dim("Structure:")
        puts lines.join("\n")
        lines
      end

      # Ruby-native tree walker
      def file_tree(root, indent: "", max_depth: 3, depth: 0, exclude: [])
        return [] if max_depth && depth >= max_depth

        entries = Dir.children(root).sort.reject { |e| exclude.include?(e) }
        lines = []

        entries.each_with_index do |entry, i|
          path = File.join(root, entry)
          last = i == entries.size - 1
          connector = last ? "+-- " : "|-- "
          lines << "#{indent}#{connector}#{entry}"

          if File.directory?(path)
            extension = last ? "    " : "|   "
            lines.concat(file_tree(path, indent: "#{indent}#{extension}", max_depth: max_depth, depth: depth + 1, exclude: exclude))
          end
        end

        lines
      end

      def detect_sprawl(path)
        large_files = []

        Dir.glob(File.join(path, "**", "*.rb")).each do |file|
          lines = File.readlines(file).size
          if lines > 500
            large_files << { file: file, lines: lines }
          end
        end

        if large_files.any?
          UI.warn("sprawl: #{large_files.size} files >500 lines")
        end

        large_files
      end

      def check_git_status(path)
        return nil unless system("git", "-C", path, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        status = `git -C #{Shellwords.escape(path)} status --porcelain`.strip

        if status.empty?
          UI.success("git status clean")
        else
          UI.warn("git: #{status.lines.size} uncommitted")
        end

        status
      end

      def recent_commits(path, limit: 5)
        return [] unless system("git", "-C", path, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        output = `git -C #{Shellwords.escape(path)} log --oneline --decorate -#{limit} 2>/dev/null`
        commits = output.lines.map(&:strip).reject(&:empty?)
        unless commits.empty?
          puts UI.dim("\nRecent commits:")
          commits.each { |line| puts line }
        end
        commits
      end

      def warn_if_issues(results)
        # Individual checks already printed. Nothing extra needed.
      end
    end
  end
end
