# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "../../trace/self_evolution_trigger"
require_relative "../../trace/snapshot_publisher"

module Master
  module CLI
    module CommandRegistry
      module_function

      SKIP_SEGS = Master::Trace::SnapshotPublisher::SKIP_SEGS

      def system_commands(agent:, diag:, root:, session: nil, bus: nil, scanner: nil, ai: nil)
        container = { session:, config: {}, root:, bus: }
        {
          "tools" => command(:dispatch_tools, root, ai),
          "tree" => command(:dispatch_tree, root),
          "diff" => command(:dispatch_diff, root),
          "commit" => command(:dispatch_commit, agent, root, review_gate: true),
          "snapshot" => command(:dispatch_snapshot, root),
          "diag" => command(:dispatch_diag, diag),
          "reload" => command(:dispatch_reload),
          "propose" => command(:dispatch_propose_suggest, container),
          "context" => command(:dispatch_context_window, session, root),
          "verify" => command(:dispatch_verify_wired, scanner, root),
          "doctor" => command(:dispatch_doctor, root),
          "pair" => command(:dispatch_pair, root),
          "security-audit" => command(:dispatch_security_audit, root),
        }
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
        out, = Master::Io::Exec.capture2e("git", "-C", root, "diff", base, "--stat")
        out.strip.empty? ? "(no changes since #{base})" : out.strip
      end

      def dispatch_commit(agent, root, ctx: nil)
        diff, = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--cached", "--stat")
        diff, = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--stat") if diff.strip.empty?
        return "nothing to commit" if diff.strip.empty?
        evolution = Master::Trace::SelfEvolutionTrigger.new(root:).call
        prompt = "Write a concise git commit message (1 line, imperative mood) for:\n#{diff}"
        commit_message = agent.ask_once(prompt).to_s.strip.lines.first.to_s.strip
        Master::Io::Exec.capture2e("git", "-C", root, "add", "-u")
        out, = Master::Io::Exec.capture2e("git", "-C", root, "commit", "-m", commit_message)
        [evolution, out.strip].reject(&:empty?).join("\n")
      end

      def dispatch_snapshot(root, ctx: nil)
        repo_root = File.expand_path("..", root)
        pub = Master::Trace::SnapshotPublisher
        [
          pub.write(target: root, label: "MASTER", repo_root:, mode: :archive),
          pub.write(target: File.expand_path("../OPENBSD", root), label: "OPENBSD", repo_root:, mode: :archive),
          pub.write(target: File.expand_path("../studio", root), label: "STUDIO", repo_root:, mode: :archive),
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
        rows = Master::CLI::Propose.new(container:).call
        return "propose: nothing pressing — try /history or scan a dir" if rows.empty?

        rows.first(5).map.with_index do |row, index|
          format("%d. %s — %s", index + 1, row.action, row.reason)
        end.join("\n")
      end

      def dispatch_context_window(session, root, ctx: nil)
        est = session.respond_to?(:token_est) ? session.token_est : 0
        limit = Master.context_window
        plan = Master::Ground::ActivePlan.read(root)
        lines = [
          "context: #{est}/#{limit} tokens (#{((est.to_f / limit) * 100).round(1)}%)",
          "topic: #{session.respond_to?(:topic) ? session.topic : 'none'}",
          "plan: #{plan.to_s.strip.empty? ? '(none)' : plan.lines.first.to_s.strip}",
        ]
        lines.join("\n")
      end

      def dispatch_verify_wired(scanner, root, ctx: nil)
        return "verify: scanner not configured" unless scanner

        out = Master::Review::Scan::SelfScan.new(scanner:, root:, event_bus: nil).call(stream: false, autofix: false)
        out.ok? ? "verify: scan clean (#{out.value!.line})" : "verify: #{out.message}"
      rescue StandardError => e
        "verify: #{e.message}"
      end

      def dispatch_tools(_root, ai, ctx: nil)
        registered = Master::Builder.tool_map.keys.sort
        wired = Array(ai&.dig(:tools)).map { |t| t.class.name.split("::").last }.sort
        [
          "tools",
          "io     #{registered.join(' ')}",
          "agent  #{wired.size} wired #{wired.empty? ? '' : wired.join(' ')}",
          "docs   data/tools.yml",
        ].join("\n")
      end

      def dispatch_pair(root, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "", "status"
          Master::Ground::Pairing.status.inspect
        when /\Aissue(?:\s+(.*))?\z/
          issued = Master::Ground::Pairing.issue(root:, label: $1.to_s.strip)
          "pair code #{issued[:code]} expires in #{issued[:expires_in]}s — redeem via /pair #{issued[:code]} or the face field"
        when "list"
          rows = Master::Ground::Pairing.list(root:)
          return "pair: no allowlist entries" if rows.empty?

          rows.map { |row| "#{row[:subject]} #{row[:label]}".strip }.join("\n")
        when /\Arevoke\s+(\S+)\z/
          Master::Ground::Pairing.revoke($1, root:) ? "pair: revoked" : "pair: not found"
        else
          result = Master::Ground::Pairing.redeem(arg.split.first, root:)
          return "pair: invalid or expired code" unless result

          Fiber[:master_paired] = true
          Fiber[:master_pair_subject] = result[:subject]
          Master::Ground::Pairing.redeem_notice(result)
        end
      end

      def dispatch_security_audit(root, ctx: nil)
        Master::Ground::SecurityAudit.report(root:)
      end

      def dispatch_doctor(root, ctx: nil)
        script = File.join(root, "bin", "doctor")
        body = if File.file?(script)
                 out, err, status = Master::Io::Exec.capture3(Gem.ruby, script, chdir: root)
                 text = [out, err].map(&:strip).reject(&:empty?).join("\n")
                 status.success? ? text : "#{text}\ndoctor: exit #{status.exitstatus}"
               else
                 "doctor: missing #{script}"
               end
        audit = Master::Ground::SecurityAudit.report(root:)
        [body, audit].reject { |part| part.to_s.strip.empty? }.join("\n")
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
      rescue Errno::EACCES, Errno::ENOENT => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.walk_tree")
        nil
      end

    end
  end
end
