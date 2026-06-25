# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"
require_relative "../../trace/self_evolution_trigger"

module Master
  module Now
    module CommandRegistry
      module_function

      TEXT_EXTS = %w[.rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json .toml .gemspec .txt .erb .conf .ini .env].to_set.freeze
      TEXT_NAMES = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
      SKIP_SEGS = %w[.git vendor tmp var node_modules .bundle coverage log dist knowledge].to_set.freeze

      def system_commands(agent:, diag:, root:, session: nil, bus: nil, scanner: nil)
        container = { session: session, config: {}, root: root, bus: bus }
        {
          "orient" => command(:dispatch_orient, root),
          "explain" => command(:dispatch_orient, root),
          "tree" => command(:dispatch_tree, root),
          "diff" => command(:dispatch_diff, root),
          "commit" => command(:dispatch_commit, agent, root),
          "snapshot" => command(:dispatch_snapshot, root),
          "diag" => command(:dispatch_diag, diag),
          "reload" => command(:dispatch_reload),
          "propose" => command(:dispatch_propose_suggest, container),
          "context" => command(:dispatch_context_window, session, root),
          "verify" => command(:dispatch_verify_wired, scanner, root),
          "doctor" => command(:dispatch_doctor, root),
        }
      end

      ORIENT_FILES = {
        "soul" => ["data/soul.yml", "constitution: axioms, voice, persona, prompt order"],
        "rules" => ["data/rules.yml", "universal cross-disciplinary rules"],
        "style" => ["data/style.yml", "ruby/shell/git/css/html/typography idioms"],
        "limits" => ["data/limits.yml", "agent loops, pipeline, council, gates"],
        "workflow" => ["data/limits.yml", "legacy alias for limits"],
        "orders" => ["data/state.yml", "event triggers and standing operating procedures"],
        "patterns" => ["data/patterns.yml", "gh/openbsd/zsh tool idioms"],
        "openbsd" => ["data/openbsd.yml", "pf/nsd/httpd/relayd config validators"],
      }.freeze

      def dispatch_orient(root, ctx: nil)
        arg = arg_for(ctx)
        return cat_orient(root, arg) unless arg.empty?
        [
          "MASTER — constitutional AI runtime for any text artifact",
          "modules: now · loop · judge · voice · ground · reach · trace",
          "rules: #{Master.rule_count(root: root)} registered",
          "pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render",
          "",
          "authority:",
          *Master.authority_paths(root: root).map { |label, path| "  #{label.ljust(10)} #{relative_or_absolute(root, path)}" },
          "",
          "constitution:",
          *ORIENT_FILES.map { |k, (path, desc)| "  /orient #{k.ljust(10)} #{path.ljust(28)} #{desc}" },
        ].join("\n")
      end

      def relative_or_absolute(root, path)
        expanded_root = File.expand_path(root)
        expanded_path = File.expand_path(path)
        return expanded_path.delete_prefix("#{expanded_root}/") if expanded_path.start_with?("#{expanded_root}/")

        expanded_path
      end

      def cat_orient(root, arg)
        entry = ORIENT_FILES[arg]
        return "unknown: #{arg} (try: #{ORIENT_FILES.keys.join(", ")})" unless entry
        full = File.join(root, entry[0])
        File.exist?(full) ? File.read(full) : "missing: #{full}"
      end

      def dispatch_tree(root, ctx: nil)
        arg = arg_for(ctx)
        cfg   = (Master.load_yaml(File.join(root, "data", "rules.yml")) || {}).dig("paths", "tree") || {}
        depth = arg.to_i.positive? ? arg.to_i : (cfg["max_depth"] || 2)
        cap   = cfg["max_lines"] || 200
        tree_lines = []
        walk_tree(root, 1, depth:, cap:, tree_lines:)
        tree_lines.join("\n")
      end

      def dispatch_diff(root, ctx: nil)
        arg = arg_for(ctx)
        base = arg.empty? ? "HEAD" : arg
        out, = Open3.capture2e("git", "-C", root, "diff", base, "--stat")
        out.strip.empty? ? "(no changes since #{base})" : out.strip
      end

      def dispatch_commit(agent, root, ctx: nil)
        diff, = Open3.capture2e("git", "-C", root, "diff", "--cached", "--stat")
        diff, = Open3.capture2e("git", "-C", root, "diff", "--stat") if diff.strip.empty?
        return "nothing to commit" if diff.strip.empty?
        evolution = Master::Trace::SelfEvolutionTrigger.new(root:).call
        prompt = "Write a concise git commit message (1 line, imperative mood) for:\n#{diff}"
        commit_message = agent.ask_once(prompt).to_s.strip.lines.first.to_s.strip
        Open3.capture2e("git", "-C", root, "add", "-u")
        out, = Open3.capture2e("git", "-C", root, "commit", "-m", commit_message)
        [evolution, out.strip].reject(&:empty?).join("\n")
      end

      def dispatch_snapshot(root, ctx: nil)
        repo_root = File.expand_path("..", root)
        lines = [
          publish_snapshot_digest(root, "MASTER", repo_root:),
          publish_snapshot_digest(File.expand_path("../DEPLOY", root), "DEPLOY", repo_root:),
          publish_snapshot(root, "MASTER"),
          publish_snapshot(File.expand_path("../DEPLOY", root), "DEPLOY"),
        ]
        lines.join("\n")
      end

      def publish_snapshot_digest(target, label, repo_root:)
        return "snapshot:#{label.downcase}: digest skipped (missing dir)" unless File.directory?(target)

        stats = snapshot_runtime_stats(target) if label == "MASTER"
        git = snapshot_git_summary(repo_root)
        body, files, n_lines = build_snapshot_markdown(target, label)
        stamp = Time.now.utc.iso8601
        digest = [
          "# #{label} Snapshot",
          "Generated: #{stamp}",
          "",
          "## Summary",
          "- files: #{files.size}",
          "- lines: #{n_lines}",
          "- target: `#{target}`",
          *(stats || []),
          *(git || []),
          "",
          "## Recent changes",
          snapshot_recent_commits(repo_root),
          ""
        ].join("\n")
        out = File.join(repo_root, "#{label}_snapshot.md")
        File.write(out, digest)
        "snapshot:#{label.downcase}: digest → #{out}"
      rescue StandardError => e
        "snapshot:#{label.downcase}: digest failed: #{e.message}"
      end

      def snapshot_runtime_stats(root)
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

      def snapshot_git_summary(repo_root)
        return [] unless File.directory?(File.join(repo_root, ".git"))

        branch, = Open3.capture2e("git", "-C", repo_root, "rev-parse", "--abbrev-ref", "HEAD")
        sha, = Open3.capture2e("git", "-C", repo_root, "rev-parse", "--short", "HEAD")
        [
          "- git: #{branch.strip} @ #{sha.strip}"
        ]
      rescue StandardError
        []
      end

      def snapshot_recent_commits(repo_root, n = 5)
        out, status = Open3.capture2e("git", "-C", repo_root, "log", "-n", n.to_s, "--oneline")
        return "(no git log)" unless status.success?

        out.lines.map(&:strip).reject(&:empty?).map { |line| "- #{line}" }.join("\n")
      rescue StandardError
        "(git unavailable)"
      end

      def dispatch_diag(diag, ctx: nil)
        arg = arg_for(ctx)
        diag ? diag.render(arg) : "diag: not configured"
      end

      def dispatch_reload(ctx: nil)
        "reload: not supported in this context"
      end

      def dispatch_propose_suggest(container, ctx: nil)
        rows = Master::Now::Propose.new(container: container).call
        return "propose: nothing pressing — try /history or scan a dir" if rows.empty?

        rows.first(5).map.with_index do |row, index|
          format("%d. %s — %s", index + 1, row.action, row.reason)
        end.join("\n")
      end

      def dispatch_context_window(session, root, ctx: nil)
        est = session.respond_to?(:token_est) ? session.token_est : 0
        limit = Master::CTX_WINDOW_SIZE
        plan = Master::Ground::ActivePlan.read(root)
        lines = [
          "context: #{est}/#{limit} tokens (#{((est.to_f / limit) * 100).round(1)}%)",
          "topic: #{session.respond_to?(:topic) ? session.topic : 'none'}",
          "plan: #{plan.to_s.strip.empty? ? '(none)' : plan.lines.first.to_s.strip}"
        ]
        lines.join("\n")
      end

      def dispatch_verify_wired(scanner, root, ctx: nil)
        return "verify: scanner not configured" unless scanner

        out = Master::Judge::Scan::SelfScan.new(scanner: scanner, root: root, event_bus: nil).call(stream: false, autofix: false)
        out.ok? ? "verify: scan clean (#{out.value!.line})" : "verify: #{out.message}"
      rescue StandardError => e
        "verify: #{e.message}"
      end

      def dispatch_doctor(root, ctx: nil)
        script = File.join(root, "bin", "doctor")
        return "doctor: missing #{script}" unless File.file?(script)

        out, err, status = Open3.capture3(Gem.ruby, script, chdir: root)
        body = [out, err].map(&:strip).reject(&:empty?).join("\n")
        status.success? ? body : "#{body}\ndoctor: exit #{status.exitstatus}"
      end

      def snapshot_output_dir
        File.expand_path(ENV.fetch("MASTER_SNAPSHOT_DIR", "~/Downloads"))
      end

      def publish_snapshot(target, label)
        return "snapshot:#{label.downcase}: not found: #{target}" unless File.directory?(target)

        body, files, n_lines = build_snapshot_markdown(target, label)
        day = Time.now.strftime("%Y-%m-%d")
        out_path = File.join(snapshot_output_dir, "#{label}_snapshot_#{day}.md")
        FileUtils.mkdir_p(File.dirname(out_path))
        File.write(out_path, body)
        "snapshot:#{label.downcase}: #{files.size} files #{n_lines} lines → #{out_path}"
      rescue StandardError => e
        "snapshot:#{label.downcase}: write failed: #{e.message}"
      end

      def build_snapshot_markdown(target, label)
        all = Dir.glob(File.join(target, "**", "*"))
               .reject { |f| File.basename(f).start_with?(".") }
               .reject { |f| skipped_snapshot_path?(f.delete_prefix("#{target}/")) }.sort
        dirs = all.select { |f| File.directory?(f) }
        files = all.select { |f| File.file?(f) && snapshot_text_file?(f) && File.size(f) < Master::CTX_WINDOW_SIZE }
        stamp = Time.now.utc.iso8601
        md = ["# #{label} Snapshot — #{stamp}", "", "## Tree", "```"]
        entries = (dirs.map { |d| [d, :dir] } + files.map { |f| [f, :file] })
                  .sort_by { |p, _| p.split("/") }
                  .map { |p, k| "#{"  " * p.delete_prefix("#{target}/").count("/")}#{File.basename(p)}#{k == :dir ? "/" : ""}" }
        md.concat(entries) << "```" << ""
        md.concat(snapshot_artifacts(target)) if label == "MASTER"
        n_lines = 0
        files.each do |f|
          rel = f.delete_prefix("#{target}/")
          lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
          body = File.read(f, encoding: "UTF-8", invalid: :replace).lines
          n_lines += body.size
          md << "## `#{rel}`" << "```#{lang}"
          md.concat(body.map(&:rstrip))
          md << "```" << ""
        rescue StandardError => e
          md << "## `#{rel}`" << "[skipped: #{e.message}]" << ""
        end
        md << "files: #{files.size} / lines: #{n_lines}"
        [md.join("\n"), files, n_lines]
      end

      def snapshot_artifacts(target)
        repo_root = File.expand_path("..", target)
        paths = %w[MASTER_snapshot.md DEPLOY_snapshot.md].filter_map do |name|
          path = File.join(repo_root, name)
          next unless File.file?(path)
          "- `#{name}` (#{File.size(path)} bytes, updated #{File.mtime(path).utc.iso8601})"
        end
        return [] if paths.empty?

        ["## Root snapshot artifacts", *paths, ""]
      end

      def arg_for(ctx) = ctx.to_h.fetch(:args, "").to_s.strip

      def walk_tree(dir, level, depth:, cap:, tree_lines:)
        return if level > depth || tree_lines.size >= cap

        Dir.children(dir).sort.each do |name|
          break if tree_lines.size >= cap
          next if name.start_with?(".") || SKIP_SEGS.include?(name)

          path = File.join(dir, name)
          tree_lines << "#{"  " * (level - 1)}#{name}#{File.directory?(path) ? "/" : ""}"
          walk_tree(path, level + 1, depth:, cap:, tree_lines:) if File.directory?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT
        nil
      end

      def skipped_snapshot_path?(rel)
        rel.split("/").any? { |segment| SKIP_SEGS.include?(segment) }
      end

      def snapshot_text_file?(file)
        TEXT_EXTS.include?(File.extname(file).downcase) || TEXT_NAMES.include?(File.basename(file))
      end
    end
  end
end
