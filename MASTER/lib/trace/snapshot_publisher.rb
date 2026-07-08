# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

require_relative "snapshot_agent_guide"

module Master
  module Trace
    # Canonical snapshot builder — tree walk, agent preamble, Downloads output.
    module SnapshotPublisher
      TEXT_EXTS = %w[.rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json .toml .gemspec .txt .erb .conf .ini .env].to_set.freeze
      TEXT_NAMES = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
      SKIP_SEGS = %w[.git .master vendor tmp var node_modules .bundle coverage log dist knowledge].to_set.freeze
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
        body, files, n_lines = build_markdown(target, label)
        header = summary_header(target, label, repo_root:, files:, n_lines:)
        [header + body, files, n_lines]
      end

      def artifacts_section(title: "Download snapshot artifacts")
        dir = output_dir
        paths = %w[MASTER_snapshot.md DEPLOY_snapshot.md].filter_map do |name|
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

      def build_markdown(target, label)
        all = snapshot_paths(target)
        dirs = all.select { |f| File.directory?(f) }
        files = all.select { |f| File.file?(f) }
        md = ["## Tree", "```"]
        entries = (dirs.map { |d| [d, :dir] } + files.map { |f| [f, :file] })
                  .sort_by { |p, _| p.split("/") }
                  .map { |p, k| "#{"  " * p.delete_prefix("#{target}/").count("/")}#{File.basename(p)}#{k == :dir ? "/" : ""}" }
        md.concat(entries) << "```" << ""
        md.concat(artifacts_section) if label == "MASTER"
        md << "## Codebase" << ""
        n_lines = 0
        files.each do |f|
          rel = f.delete_prefix("#{target}/")
          section, line_count = file_section(f)
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
          "- policy: full tree + every file verbatim (no truncation)",
          *(stats || []),
          *(git || []),
          "",
          "## Recent changes",
          recent_commits(repo_root),
          ""
        ].join("\n")
      end

      def snapshot_paths(target)
        Dir.glob(File.join(target, "**", "*"), File::FNM_DOTMATCH)
           .reject { |f| skip_entry?(f.delete_prefix("#{target}/").delete_prefix("/")) }
           .sort
      end

      def skip_entry?(rel)
        return true if rel.empty? || rel == "."

        rel.split("/").any? { |segment| segment == "." || segment == ".." || SKIP_SEGS.include?(segment) }
      end

      def file_section(path)
        size = File.size(path)
        return [["_binary: #{size} bytes (not inlined)_"], 0] unless text_file?(path)
        return [["_text: #{size} bytes over #{MAX_INLINE_BYTES} cap (not inlined)_"], 0] if size > MAX_INLINE_BYTES

        text = File.read(path, encoding: "UTF-8", invalid: :replace)
        lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(path).downcase, "text")
        lines = text.each_line.map(&:rstrip)
        [["```#{lang}", *lines, "```"], lines.size]
      rescue StandardError => e
        [["```text", "[unreadable: #{e.message}]", "```"], 1]
      end

      def text_file?(file)
        TEXT_EXTS.include?(File.extname(file).downcase) || TEXT_NAMES.include?(File.basename(file))
      end

      def runtime_stats(root)
        return [] unless File.directory?(File.join(root, "data/runtime"))

        pending = implemented = 0
        path = File.join(root, "data/runtime/face_enhancements.yml")
        if File.file?(path)
          data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
          Array(data["enhancements"]).each do |row|
            case row["status"].to_s
            when "implemented" then implemented += 1
            when "pending" then pending += 1
            end
          end
        end
        cfg = File.join(root, "data/runtime/runtime.yml")
        enhancements = []
        if File.file?(cfg)
          raw = YAML.safe_load_file(cfg, permitted_classes: [Symbol], aliases: true) || {}
          enhancements = Array(raw["enhancements"])
        end
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
