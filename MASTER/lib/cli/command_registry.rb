# frozen_string_literal: true

require_relative "command_registry/command"
require_relative "command_registry/formatter"
require_relative "command_registry/help"
require_relative "command_registry/memory_commands"
require_relative "command_registry/work_commands"
require_relative "command_registry/system_commands"
require_relative "command_registry/media_commands"
require_relative "command_registry/core_commands"
require_relative "command_registry/domain_commands"
require_relative "command_registry/reach_commands"
require_relative "command_registry/agent_commands"
require "open3"

module Master
  module CLI
    module CommandRegistry
      module_function

      def build_fast(infra:, ai:, root:)
        bus = infra[:bus]
        git = Io::GitOperations.new(File.expand_path("..", root))
        trace = infra[:trace]
        {
          "status" => Command.new do |ctx|
            dispatch_status(root:, fix_loop: nil, bus:, git:, trace:, ctx:)
          end,
          "help" => command(:help_text, nil),
        }
      end

      # Closed public surface. Scan/fix/critique stay as methods ThroughPipeline
      # calls; they are not slash verbs.
      def build(infra:, ai:, root:)
        d = work_command_deps(ai:, root:, infra:)
        undo = infra[:undo]
        {
          "through" => command(:dispatch_through, d[:scanner], d[:fix_loop], d[:deliberation], d[:root], d[:bus], d[:review_crew]),
          "status" => command(:dispatch_status, d[:root], d[:fix_loop], d[:bus], d[:git], d[:trace]),
          "undo" => command(:dispatch_undo, undo),
          "rollback" => command(:dispatch_undo, undo),
          "clear" => command(:dispatch_clear, infra[:session]),
          "commit" => command(:dispatch_commit, ai[:agent], root, review_gate: true),
          "model" => command(:dispatch_model, d[:agent], d[:config], d[:metrics], d[:root]),
          "pair" => command(:dispatch_pair, root),
          "doctor" => command(:dispatch_doctor, root),
          "why" => command(:dispatch_why, d[:agent], d[:root]),
          "help" => command(:help_text, nil),
        }
      end

      def dispatch_clear(session, ctx: nil)
        session.clear!
        "context cleared"
      end

      def dispatch_save(session, ctx: nil)
        session.save!
        "session saved"
      end

      def dispatch_history(session, ctx: nil)
        n = arg_for(ctx).to_i
        n = 10 if n <= 0
        recent = session.messages.last(n)
        return "history: empty" if recent.empty?

        recent.map.with_index(1) { |m, i| Formatter.history_line(m, i) }.join("\n")
      end

      def dispatch_grep(session, ctx: nil)
        grep_history(session, arg_for(ctx))
      end

      def dispatch_audit(config, ctx: nil)
        audit_changes(config["root"] || Dir.pwd)
      end

      def dispatch_tokens(session, ctx: nil)
        "~#{session.token_est} tokens"
      end

      def dispatch_cost(session, ctx: nil)
        Formatter.cost(session.cost)
      end

      def dispatch_undo(undo, ctx: nil)
        r = undo.undo!
        r.ok? ? "reverted: #{r.value!}" : r.message
      end

      def dispatch_rollback(undo, ctx: nil)
        r = undo.undo!
        r.ok? ? "rolled back: #{r.value!}" : r.message
      end

      def dispatch_redo(undo, ctx: nil)
        r = undo.redo!
        r.ok? ? "reapplied: #{r.value!}" : r.message
      end

      def dispatch_dmesg(logging, ctx: nil)
        n = arg_for(ctx).to_i
        logging.dmesg(n.positive? ? n : Master::Trace::Logging::DEFAULT_DMESG_LINES)
      end

      def dispatch_config(config, ctx: nil)
        config.to_h.inspect
      end

      def dispatch_reasoning(config, ctx: nil)
        arg = arg_for(ctx)
        Master::Review::Modes::SUPPORTED.include?(arg) ?
          (config["reasoning_mode"] = arg; config.save!; "reasoning: #{arg}") :
          "reasoning: #{config.reasoning_mode} (supported: #{Master::Review::Modes::SUPPORTED.join(", ")})"
      end

      def dispatch_task(config, ctx: nil)
        arg = arg_for(ctx)
        arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}")
      end

      def dispatch_persona(config, ctx: nil)
        arg = arg_for(ctx)
        return "persona: #{config.persona}" if arg.empty?

        known = Master::Voice::Personality.persona_names.map(&:to_s)
        unless known.include?(arg.downcase)
          return "persona: '#{arg}' isn't a known persona (#{known.join(', ')}) -- unchanged, still #{config.persona}"
        end

        config["persona"] = arg.downcase
        config.save!
        "persona: #{arg.downcase}"
      end

      def dispatch_flag(config, flag, ctx: nil)
        arg = arg_for(ctx)
        arg.empty? ? "#{flag}: #{config[flag]}" : (config[flag] = arg == "on"; config.save!; "#{flag}: #{config[flag]}")
      end

      def grep_history(session, pattern)
        needle = pattern.to_s.strip
        return "usage: /grep <pattern>" if needle.empty?

        rows = session.messages.select { |msg| msg[:content].to_s.match?(Regexp.new(Regexp.escape(needle), Regexp::IGNORECASE)) }
        return "grep: no matches" if rows.empty?

        rows.last(20).map { |msg| "[#{msg[:role]}] #{msg[:content].to_s.gsub(/\s+/, " ")[0, 160]}" }.join("\n")
      end

      def audit_changes(root)
        out, status = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--numstat", "HEAD")
        return "audit: unavailable" unless status.success?
        rows = out.lines.map(&:strip).reject(&:empty?)
        return "audit: clean" if rows.empty?

        rows.map { |line| Formatter.audit_numstat(line) }.join("\n")
      rescue StandardError => e
        "audit: #{e.message}"
      end

      def control_commands(standing, soul)
        {
          "orders" => command(:dispatch_orders, standing),
          "soul" => command(:dispatch_soul, soul),
        }
      end

      def dispatch_orders(standing, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "list", "" then standing.list
        when /\Aenable (.+)\z/ then standing.enable($1.strip)
        when /\Adisable (.+)\z/ then standing.disable($1.strip)
        when /\Aadd name=(\S+) cmd=(.+)\z/ then standing.upsert(name: $1, command: $2.strip)
        when "run" then run_due_orders(standing)
        when /\Areset (.+)\z/ then standing.reset($1.strip)
        else "usage: /orders  /orders enable|disable|reset <name>  /orders run"
        end
      end

      def run_due_orders(standing)
        results = standing.run_due!
        return "no orders due" if results.empty?
        results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      end

      def dispatch_soul(soul, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "", "show" then soul.summary
        when "version", "changelog" then soul.changelog
        when "diff" then soul.diff
        when "approve" then soul.approve
        when "reject" then soul.reject
        when "rollback" then soul.rollback
        when /\Apropose (.+)\z/ then soul.propose($1.strip)
        else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
        end
      end

      def arg_for(ctx) = ctx.to_h.fetch(:args, "").to_s.strip
      def expand_or_root(arg, root) = arg.empty? ? root : File.expand_path(arg, root)
      def command(method, *args, **kwargs) = Command.new(self, method, *args, **kwargs)
      alias cmd command
    end
  end
end
