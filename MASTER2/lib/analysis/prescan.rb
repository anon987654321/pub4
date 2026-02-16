# frozen_string_literal: true

module MASTER
  module Analysis
    # Prescan - Mandatory situational awareness before touching code
    # Ported from MASTER v1 cli.rb prescan ritual
    module Prescan
      extend self

      def run(path = MASTER.root)
        results = {
          sprawl: detect_sprawl(path),
          git_status: check_git_status(path),
        }

        warn_if_issues(results)
        results
      end

      private

      def show_tree(path)
        puts UI.dim("Structure:")

        # Ruby-native tree walker - no system dependencies
        tree = file_tree(path, max_depth: 3, exclude: %w[. .. .git vendor tmp node_modules var])
        puts tree.join("\n")
        true
      end

      # Ruby-native tree walker
      def file_tree(root, indent: "", max_depth: 3, depth: 0, exclude: [])
        return [] if depth >= max_depth

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
          UI.success("git clean")
        else
          UI.warn("git: #{status.lines.size} uncommitted")
        end

        status
      end

      def show_recent_commits(path)
        return nil unless system("git -C #{path} rev-parse --git-dir > /dev/null 2>&1")

        puts UI.dim("\nRecent commits:")
        system("git", "-C", path, "log", "--oneline", "--decorate", "-5")

        true
      end

      def warn_if_issues(results)
        # Individual checks already printed. Nothing extra needed.
      end
    end
  end
end
