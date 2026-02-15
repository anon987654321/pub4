# frozen_string_literal: true

module MASTER
  module Analysis
    # Prescan - Mandatory situational awareness before touching code
    # Ported from MASTER v1 cli.rb prescan ritual
    module Prescan
      extend self

      def run(path = MASTER.root)
        puts UI.bold("\n🔍 Prescan")
        puts UI.dim("Understanding codebase state before proceeding...\n")

        results = {
          tree: show_tree(path),
          sprawl: detect_sprawl(path),
          git_status: check_git_status(path),
          recent_commits: show_recent_commits(path)
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
          connector = last ? "└── " : "├── "
          lines << "#{indent}#{connector}#{entry}"

          if File.directory?(path)
            extension = last ? "    " : "│   "
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
          puts UI.yellow("\n⚠️  Sprawl detected (#{large_files.size} files > 500 lines):")
          large_files.first(5).each do |f|
            puts "  #{File.basename(f[:file])}: #{f[:lines]} lines"
          end
        end

        large_files
      end

      def check_git_status(path)
        return nil unless system("git", "-C", path, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        status = `git -C #{Shellwords.escape(path)} status --porcelain`.strip

        if status.empty?
          puts UI.green("\n✓ Git: Clean working tree")
        else
          puts UI.yellow("\n⚠️  Git: Uncommitted changes:")
          puts status.lines.first(5).map { |l| "  #{l}" }
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
        warnings = []

        warnings << "Large files detected" if results[:sprawl]&.any?
        warnings << "Uncommitted changes" if results[:git_status] && !results[:git_status].empty?

        if warnings.any?
          puts UI.yellow("\n⚠️  Issues: #{warnings.join(', ')}")
          puts UI.dim("Consider addressing these before proceeding.\n")
        else
          puts UI.green("\n✓ All clear\n")
        end
      end
    end
  end
end
