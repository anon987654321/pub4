# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "../../trace/self_evolution_trigger"
require_relative "../../trace/snapshot_publisher"

module Master
  module Now
    module CommandRegistry
      module_function

      SKIP_SEGS = Master::Trace::SnapshotPublisher::SKIP_SEGS

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
        pub = Master::Trace::SnapshotPublisher
        [
          pub.write(target: root, label: "MASTER", repo_root:, mode: :both),
          pub.write(target: File.expand_path("../DEPLOY", root), label: "DEPLOY", repo_root:, mode: :both),
        ].flatten.join("\n")
      end

      def publish_snapshot_digest(target, label, repo_root: File.expand_path("..", target))
        Master::Trace::SnapshotPublisher.write(target:, label:, repo_root:, mode: :digest).first
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

      def snapshot_output_dir = Master::Trace::SnapshotPublisher.output_dir

      def publish_snapshot(target, label, repo_root: File.expand_path("..", target))
        Master::Trace::SnapshotPublisher.write(target:, label:, repo_root:, mode: :archive).first
      end

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

    end
  end
end
