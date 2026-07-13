# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

require_relative "snapshot_agent_guide"
require_relative "snapshot_collector"

module Master
  module Trace
    # Canonical snapshot builder — git-tracked source, agent preamble, Downloads output.
    module SnapshotPublisher
      SKIP_SEGS = SnapshotCollector::SKIP_SEGS
      BOOT_DIRS = %w[bin lib data].freeze
      BOOT_MAX_BYTES = 50_000
      # A readable snapshot inlines source, not media or generated bulk. Binaries
      # are noted (never base64-inlined — that once produced multi-GB "snapshots"),
      # and any text file past this cap is listed rather than pasted whole.
      MAX_INLINE_BYTES = 262_144

      module_function

      def output_dir
        File.expand_path(ENV.fetch("MASTER_SNAPSHOT_DIR", "~/Downloads"))
      end

      def write(target:, label:, repo_root: nil, mode: :both)
        repo_root ||= File.expand_path("..", target)
        label_key = label.to_s.downcase
        return ["snapshot:#{label_key}: not found: #{target}"] unless File.directory?(target)

        content, files, n_lines = build_document(target, label, repo_root:)
        dir = output_dir
        FileUtils.mkdir_p(dir)
        day = Time.now.strftime("%Y-%m-%d")
        paths = []
        messages = []

        if mode == :digest || mode == :both
          digest = File.join(dir, "#{label}_snapshot.md")
          File.write(digest, content)
          paths << digest
          messages << "snapshot:#{label_key}: #{files.size} files #{n_lines} lines → #{digest}"
        end

        if mode == :archive || mode == :both
          archive = File.join(dir, "#{label}_snapshot_#{day}.md")
          File.write(archive, content)
          paths << archive
          messages << "snapshot:#{label_key}: #{files.size} files #{n_lines} lines → #{archive}"
        end

        messages
      rescue StandardError => e
        ["snapshot:#{label_key}: write failed: #{e.message}"]
      end

      def build_document(target, label, repo_root:)
        body, files, n_lines = build_markdown(target, label, repo_root:)
        header = summary_header(target, label, repo_root:, files:, n_lines:)
        [header + body, files, n_lines]
      end

      def artifacts_section(title: "Download snapshot artifacts")
        dir = output_dir
        paths = %w[MASTER_snapshot.md OPERATOR_snapshot.md].filter_map do |name|
          path = File.join(dir, name)
          next unless File.file?(path)
          "- `#{path}` (#{File.size(path)} bytes, updated #{File.mtime(path).utc.iso8601})"
        end
        return [] if paths.empty?

        ["## #{title}", *paths, ""]
      end

      def boot_light(root)
        files = Dir[*BOOT_DIRS.map { |d| File.join(root, d, "**", "*") }]
          .select { |f| File.file?(f) && File.size(f) < BOOT_MAX_BYTES }
          .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
          .sort
        body = files.flat_map do |f|
          rel = f.delete_prefix("#{root}/")
          lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
          src = File.read(f, encoding: "UTF-8", invalid: :replace)
          ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
        rescue StandardError => e
          Ground::Swallow.log(e, context: "snapshot_publisher.boot_light", path: f)
          []
        end
        header = [
          "# MASTER Snapshot",
          "Generated: #{Time.now.utc.iso8601}",
          "",
          SnapshotAgentGuide.render(label: "MASTER"),
          "Files: #{files.size}",
          ""
        ]
        (header + artifacts_section + body).join("\n")
      end

      def boot_current?(root, *outputs)
        files = Dir[*BOOT_DIRS.map { |d| File.join(root, d, "**", "*") }]
          .select { |f| File.file?(f) && File.size(f) < BOOT_MAX_BYTES }
        return false if files.empty?
        return false unless outputs.all? { |path| File.exist?(path) }

        newest_source = files.map { |path| File.mtime(path) }.max
        oldest_output = outputs.map { |path| File.mtime(path) }.min
        oldest_output >= newest_source
      rescue StandardError
        false
      end

      def build_markdown(target, label, repo_root:)
        parts = SnapshotCollector.partition(SnapshotCollector.collect_paths(label:, repo_root:, target:))
        files = parts[:inlined]
        large = parts[:large]
        md = ["## Tree", "```"]
        files.each { |path| md << path.delete_prefix("#{target}/").delete_prefix("#{repo_root}/").delete_prefix("/") }
        md << "```" << ""
        unless large.empty?
          md << "## Large files (listed, not inlined)"
          large.each do |path|
            rel = path.delete_prefix("#{target}/").delete_prefix("#{repo_root}/").delete_prefix("/")
            md << "- `#{rel}` (#{(File.size(path) / 1024.0).round} KB)"
          end
          md << ""
        end
        md.concat(artifacts_section) if label == "MASTER"
        md << "## Codebase" << ""
        n_lines = 0
        files.each do |path|
          rel = path.delete_prefix("#{target}/").delete_prefix("#{repo_root}/").delete_prefix("/")
          section, line_count = SnapshotCollector.file_section(path)
          n_lines += line_count
          md << "## `#{rel}`"
          md.concat(section)
          md << ""
        end
        md << "files: #{files.size} / lines: #{n_lines}"
        [md.join("\n"), files, n_lines]
      end

      def summary_header(target, label, repo_root:, files:, n_lines:)
        stamp = Time.now.utc.iso8601
        stats = runtime_stats(target) if label == "MASTER"
        git = git_summary(repo_root)
        [
          "# #{label} Snapshot",
          "Generated: #{stamp}",
          "",
          SnapshotAgentGuide.render(label:),
          "## Summary",
          "- files: #{files.size}",
          "- lines: #{n_lines}",
          "- target: `#{target}`",
          "- policy: #{SnapshotCollector::POLICY_SUMMARY}",
          *(stats || []),
          *(git || []),
          "",
          "## Recent changes",
          recent_commits(repo_root),
          ""
        ].join("\n")
      end

      def runtime_stats(root)
        catalog_path = File.join(root, "data/runtime.yml")
        return [] unless File.file?(catalog_path)

        pending = implemented = 0
        catalog = YAML.safe_load_file(catalog_path, permitted_classes: [Symbol], aliases: true) || {}
        Array(catalog.dig("face_enhancements", "enhancements")).each do |row|
          case row["status"].to_s
          when "implemented" then implemented += 1
          when "pending" then pending += 1
          end
        end
        enhancements = Array(catalog.dig("runtime", "enhancements"))
        [
          "- runtime enhancements: #{implemented} implemented / #{pending} pending",
          "- active flags: #{enhancements.size} (#{enhancements.last(5).join(", ")})"
        ]
      end

      def git_summary(repo_root)
        return [] unless File.directory?(File.join(repo_root, ".git"))

        branch, = Master::Reach::Exec.capture2e("git", "-C", repo_root, "rev-parse", "--abbrev-ref", "HEAD")
        sha, = Master::Reach::Exec.capture2e("git", "-C", repo_root, "rev-parse", "--short", "HEAD")
        ["- git: #{branch.strip} @ #{sha.strip}"]
      rescue StandardError
        []
      end

      def recent_commits(repo_root, n = 5)
        out, status = Master::Reach::Exec.capture2e("git", "-C", repo_root, "log", "-n", n.to_s, "--oneline")
        return "(no git log)" unless status.success?

        out.lines.map(&:strip).reject(&:empty?).map { |line| "- #{line}" }.join("\n")
      rescue StandardError
        "(git unavailable)"
      end
    end
  end
end
