# frozen_string_literal: true

require_relative "../../trace/self_evolution_trigger"
require_relative "../../trace/snapshot/publisher"

module Master
  module CLI
    module CommandRegistry
      module_function

      # The dispatchers `build` reaches by symbol for /commit, /pair, /doctor and
      # /rules, and the tree walk a session prints at boot.
      SKIP_SEGS = Master::Trace::Snapshot::Publisher::SKIP_SEGS

      def dispatch_tree(root, ctx: nil)
        arg = arg_for(ctx)
        cfg = (Master.load_yaml(File.join(root, "data", "rules.yml")) || {}).dig("paths", "tree") || {}
        depth = arg.to_i.positive? ? arg.to_i : (cfg["max_depth"] || 2)
        cap = cfg["max_lines"] || 200
        tree_lines = []
        walk_tree(root, 1, depth:, cap:, tree_lines:)
        tree_lines.join("\n")
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

      # The corpus, one line each, because the instruction every agent is given is to
      # read the law before writing, and the only way to do that was a YAML one-liner
      # in CLAUDE.md that iterated the wrong shape for months.
      #
      # A list, not a copy: it reads data/rules.yml at call time, the same file
      # `bin/operator rule <ID>` prints a card from. An argument filters by id or
      # name, so `/rules guard` narrows to the rules that govern guard clauses.
      #
      # Read-only on purpose. The verb that enforces them is /review, and that now
      # needs --apply to write. A second verb that scans and fixes would be the same
      # pipeline under another name, which is the defect this repo keeps finding in
      # its own tree.
      def dispatch_rules(_root, ctx: nil)
        filter = arg_for(ctx).downcase
        rules = Master.law("rules") || []
        rows = rules.select do |rule|
          next true if filter.empty?

          "#{rule["id"]} #{rule["name"]}".downcase.include?(filter)
        end
        return "rules: nothing matches #{filter.inspect} in #{rules.size} declared" if rows.empty?

        lines = rows.map do |rule|
          kind = rule["detect_semantic"] ? "semantic" : "detector"
          format("%-28s %-10s %-8s %s", rule["id"], rule["tier"], rule["severity"], kind)
        end
        ["#{rows.size} of #{rules.size} rules — bin/operator rule <ID> for one in full", *lines].join("\n")
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

      def walk_tree(dir, level, depth:, cap:, tree_lines:)
        return if level > depth || tree_lines.size >= cap

        Dir.children(dir).sort.each do |name|
          break if tree_lines.size >= cap
          next if name.start_with?(".") || SKIP_SEGS.include?(name)

          path = File.join(dir, name)
          tree_lines << "#{" " * (level - 1)}#{name}#{File.directory?(path) ? "/" : ""}"
          walk_tree(path, level + 1, depth:, cap:, tree_lines:) if File.directory?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.walk_tree")
        nil
      end

    end
  end
end
