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
        return @cache[path] if cache && @cache.key?(path)

        tree_lines = project_tree(path, max_depth: tree_depth)
        results = {
          tree: tree_lines,
          tree_digest: Digest::SHA256.hexdigest(tree_lines.join("\n")),
          tree_nodes: tree_lines.size,
          sprawl: detect_sprawl(path),
          git_status: git_status(path),
          recent_commits: recent_commits(path),
          violations: violation_summary(path),
        }

        warn_if_issues(results)
        openbsd_config_scan if RUBY_PLATFORM.include?("openbsd") || ENV["MASTER_OPENBSD_SCAN"] == "true"
        @cache[path] = results if cache
        results
      end

      private

      def project_tree(path, max_depth: 4)
        file_tree(path, max_depth: max_depth, exclude: TREE_EXCLUDES)
      end

      # Ruby-native tree walker
      def file_tree(root, indent: "", max_depth: 3, depth: 0, exclude: [])
        return [] if max_depth && depth >= max_depth

        entries = Dir.children(root).sort.reject { |e| exclude.include?(e) }
        lines = []

        entries.each_with_index do |entry, i|
          path = File.join(root, entry)
          last = i == entries.size - 1
          connector = last ? "└── " : "├── "
          lines << "#{indent}#{connector}#{entry}"

          next unless File.directory?(path)

          extension = last ? "    " : "│   "
          lines.concat(file_tree(path, indent: "#{indent}#{extension}", max_depth: max_depth, depth: depth + 1,
                                       exclude: exclude))
        end

        lines
      end

      def detect_sprawl(path)
        large_files = []

        Dir.glob(File.join(path, "**", "*.rb")).each do |file|
          lines = File.readlines(file).size
          large_files << { file: file, lines: lines } if lines > 500
        end

        UI.warn("health0: sprawl #{large_files.size} files >500 lines") if large_files.any?

        large_files
      end

      def git_status(path)
        return nil unless system("git", "-C", path, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        status = `git -C #{Shellwords.escape(path)} status --porcelain`.strip

        if status.empty?
          # Check for unpushed commits
          unpushed = `git -C #{Shellwords.escape(path)} log @{u}..HEAD --oneline 2>/dev/null`.strip
          if unpushed.empty?
            UI.success("vcs0: clean")
          else
            count = unpushed.lines.size
            UI.warn("vcs0: #{count} unpushed commit#{count == 1 ? "" : "s"}")
          end
        else
          files = status.lines.map { |l| l.strip.split(" ", 2).last }.first(3)
          tail  = status.lines.size > 3 ? " +#{status.lines.size - 3} more" : ""
          UI.warn("vcs0: #{status.lines.size} uncommitted -- #{files.join(", ")}#{tail}")
        end

        status
      end

      def recent_commits(path, limit: 5)
        return [] unless system("git", "-C", path, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        output = `git -C #{Shellwords.escape(path)} log --oneline --decorate -#{limit} 2>/dev/null`
        commits = output.lines.map(&:strip).reject(&:empty?)
        if (ENV["MASTER_VERBOSE"] || ENV.fetch("MASTER_DEBUG", nil)) && !commits.empty?
          puts UI.dim("\nRecent commits:")
          commits.each { |line| puts line }
        end
        commits
      end

      def warn_if_issues(results)
        vs = results[:violations]
        return unless vs && vs[:total].positive?

        autofix_note = vs[:autofix_eligible].positive? ? " * #{vs[:autofix_eligible]} autofix-eligible -- run: converge" : ""
        UI.warn("quality0: #{vs[:total]} violations across #{vs[:files]} files#{autofix_note}")
      end

      # Lightweight violation tally using literal pattern matching only (no LLM).
      # Delegates to Scan.run when available; falls back to direct check otherwise.
      # Returns { total:, autofix_eligible:, files:, by_file: { path => [violations] } }
      def violation_summary(path)
        return { total: 0, autofix_eligible: 0, files: 0, by_file: {} } unless defined?(Scan)

        Scan.run(path, depth: :quick).tap { |r| r[:files] = r[:scanned] }
      rescue StandardError
        { total: 0, autofix_eligible: 0, files: 0, by_file: {} }
      end

      def openbsd_config_scan
        return unless defined?(MASTER::Analysis::OpenBSDConfigValidator)

        p = UI.pastel
        issues = OpenBSDConfigValidator.scan_dir("/etc")
        issues.each do |file, file_issues|
          fname = p.bold(File.basename(file.to_s))
          file_issues.each do |issue|
            UI.warn("pf0: #{fname}: #{issue[:message]}") if issue[:severity] == :warn
            UI.warn("pf0: #{fname}: #{issue[:message]} (man #{issue[:man]})") if issue[:severity] == :error
          end
        end
      rescue StandardError
        # non-critical -- /etc may not be readable
      end
    end
  end
end
