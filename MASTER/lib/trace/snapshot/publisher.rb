# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

require_relative "agent_guide"
require_relative "collector"

module Master
  module Trace
    module Snapshot
      # Canonical snapshot builder — git-tracked source, agent preamble, Downloads output.
      module Publisher
        SKIP_SEGS = Collector::SKIP_SEGS
        BOOT_DIRS = %w[bin lib data].freeze
        BOOT_MAX_BYTES = 50_000
        # A readable snapshot inlines source, not media or generated bulk. Binaries
        # get a path note (never base64-inlined — that once produced multi-GB "snapshots"),
        # and any text file past this cap we list instead of pasting whole.
        MAX_INLINE_BYTES = 262_144

        module_function

        # Beside the code they describe, not in ~/Downloads.
        #
        # A snapshot is a share-pack of the repo — tree listing plus every text
        # file verbatim — and writing it to the browser's download folder mixed it
        # in with everything else that lands there, left stale copies nobody
        # noticed (an OPERATOR_snapshot.md survived eighteen days after OPERATOR
        # was folded into OPENBSD, still being offered to agents by the snapshot
        # agent-guide), and made "where are the snapshots" a question with a
        # non-obvious answer.
        #
        # The repo root itself, with no containing directory. Gitignored via
        # /*_snapshot_*.md, so a ~13MB set cannot reach a commit. Not a subfolder
        # and not a dotfolder: these exist to be found and handed to something,
        # and both of those hide them.
        #
        # Every file carries its date, so the set is self-describing where it
        # lands. Same-day regeneration overwrites that day's file rather than
        # accumulating — deliberate, because unpruned 13MB sets in a repo root
        # get very expensive very quickly. If you need two distinct sets in one
        # day, point MASTER_SNAPSHOT_DIR somewhere.
        #
        # MASTER_SNAPSHOT_DIR still overrides. The ~/Downloads fallback is kept
        # for the case where this file is loaded from outside a checkout, rather
        # than writing into whatever directory happens to be current.
        def output_dir
          return File.expand_path(ENV["MASTER_SNAPSHOT_DIR"]) if ENV["MASTER_SNAPSHOT_DIR"]

          # lib/trace -> lib -> MASTER -> pub4. Three levels, not four: the first
          # ".." already leaves the trace/ directory.
          repo = File.expand_path("../../..", __dir__)
          File.directory?(File.join(repo, ".git")) ? repo : File.expand_path("~/Downloads")
        end

        def write(target:, label:, repo_root: nil, mode: :both)
          repo_root ||= File.expand_path("..", target)
          label_key = label.to_s.downcase
          return ["snapshot:#{label_key}: not found: #{target}"] unless File.directory?(target)

          content, files, n_lines = build_document(target, label, repo_root:)
          dir = output_dir
          FileUtils.mkdir_p(dir)

          write_snapshot_variants(dir, label, label_key, content, files:, n_lines:, mode:)
        rescue StandardError => e
          ["snapshot:#{label_key}: write failed: #{e.message}"]
        end

        def write_snapshot_variants(dir, label, label_key, content, files:, n_lines:, mode:)
          messages = []
          if mode == :digest || mode == :both
            digest = File.join(dir, "#{label}_snapshot.md")
            messages << write_snapshot_file(digest, content, label_key:, files:, n_lines:)
          end

          if mode == :archive || mode == :both
            day = Time.now.strftime("%Y-%m-%d")
            archive = File.join(dir, "#{label}_snapshot_#{day}.md")
            messages << write_snapshot_file(archive, content, label_key:, files:, n_lines:)
          end

          messages
        end

        def write_snapshot_file(path, content, label_key:, files:, n_lines:)
          File.write(path, content)
          "snapshot:#{label_key}: #{files.size} files #{n_lines} lines → #{path}"
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
          body = files.flat_map { |f| render_boot_light_file(f, root) }
          (boot_light_header(files.size) + artifacts_section + body).join("\n")
        end

        def render_boot_light_file(f, root)
          rel = f.delete_prefix("#{root}/")
          lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
          src = File.read(f, encoding: "UTF-8", invalid: :replace)
          ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
        rescue StandardError => e
          Ground::Swallow.log(e, context: "Snapshot::Publisher.boot_light", path: f)
          []
        end

        def boot_light_header(file_count)
          [
            "# MASTER Snapshot",
            "Generated: #{Time.now.utc.iso8601}",
            "",
            AgentGuide.render(label: "MASTER"),
            "Files: #{file_count}",
            "",
          ]
        end

        def boot_current?(root, *outputs)
          files = Dir[*BOOT_DIRS.map { |d| File.join(root, d, "**", "*") }]
            .select { |f| File.file?(f) && File.size(f) < BOOT_MAX_BYTES }
          return false if files.empty?
          return false unless outputs.all? { |path| File.exist?(path) }

          newest_source = files.map { |path| File.mtime(path) }.max
          oldest_output = outputs.map { |path| File.mtime(path) }.min
          oldest_output >= newest_source
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Snapshot::Publisher.boot_current?")
          false
        end

        def build_markdown(target, label, repo_root:)
          parts = Collector.partition(Collector.collect_paths(label:, repo_root:, target:))
          files = parts[:inlined]
          large = parts[:large]

          md = tree_and_large_files_lines(files, large, target, repo_root)
          md.concat(artifacts_section) if label == "MASTER"
          md << "## Codebase" << ""
          body, n_lines = codebase_lines(files, target, repo_root)
          md.concat(body)
          md << "files: #{files.size} / lines: #{n_lines}"
          [md.join("\n"), files, n_lines]
        end

        def tree_and_large_files_lines(files, large, target, repo_root)
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
          md
        end

        def codebase_lines(files, target, repo_root)
          md = []
          n_lines = 0
          files.each do |path|
            rel = path.delete_prefix("#{target}/").delete_prefix("#{repo_root}/").delete_prefix("/")
            section, line_count = Collector.file_section(path)
            n_lines += line_count
            md << "## `#{rel}`"
            md.concat(section)
            md << ""
          end
          [md, n_lines]
        end

        def summary_header(target, label, repo_root:, files:, n_lines:)
          stamp = Time.now.utc.iso8601
          stats = runtime_stats(target) if label == "MASTER"
          git = git_summary(repo_root)
          summary_lines(target, label, stamp, files:, n_lines:, stats:, git:, repo_root:).join("\n")
        end

        def summary_lines(target, label, stamp, files:, n_lines:, stats:, git:, repo_root:)
          [
            "# #{label} Snapshot",
            "Generated: #{stamp}",
            "",
            AgentGuide.render(label:),
            "## Summary",
            "- files: #{files.size}",
            "- lines: #{n_lines}",
            "- target: `#{target}`",
            "- policy: #{Collector::POLICY_SUMMARY}",
            *Array(stats),
            *Array(git),
            "",
            "## Recent changes",
            recent_commits(repo_root),
            "",
          ]
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
            "- active flags: #{enhancements.size} (#{enhancements.last(5).join(", ")})",
          ]
        end

        def git_summary(repo_root)
          return [] unless File.directory?(File.join(repo_root, ".git"))

          branch, = Master::Io::Exec.capture2e("git", "-C", repo_root, "rev-parse", "--abbrev-ref", "HEAD")
          sha, = Master::Io::Exec.capture2e("git", "-C", repo_root, "rev-parse", "--short", "HEAD")
          ["- git: #{branch.strip} @ #{sha.strip}"]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Snapshot::Publisher.git_summary")
          []
        end

        def recent_commits(repo_root, n = 5)
          out, status = Master::Io::Exec.capture2e("git", "-C", repo_root, "log", "-n", n.to_s, "--oneline")
          return "(no git log)" unless status.success?

          out.lines.map(&:strip).reject(&:empty?).map { |line| "- #{line}" }.join("\n")
        rescue StandardError
          "(git unavailable)"
        end
      end
    end
  end
end
