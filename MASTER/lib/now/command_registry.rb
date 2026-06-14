# frozen_string_literal: true

require_relative "command_registry/command"
require_relative "command_registry/formatter"
require_relative "command_registry/memory_commands"
require_relative "command_registry/work_commands"
require_relative "command_registry/system_commands"
require_relative "command_registry/tool_commands"
require "open3"

module Master
  module Now
    module CommandRegistry
      module_function

      HELP_TOPICS = {
        "run" => {
          summary: "natural-language task entry point",
          detail: ["/run <task>", "Routes intent through the pipeline and chooses the handler."]
        },
        "scan" => {
          summary: "deep-scan files or directories",
          detail: ["/scan [--dry-run] [--profile NAME|profile] [path]", "Profiles: quick, full, axioms_only, solid_focus, critical. Dry-run reports findings without changes."]
        },
        "self" => {
          summary: "scan MASTER itself",
          detail: ["/self", "Runs the MASTER self-scan with stream output."]
        },
        "fix" => {
          summary: "run or preview fixes for a target",
          detail: ["/fix [path]", "/fix --dry-run [path]", "/fix preview [path]", "Background control lives under /watch on|off|status."]
        },
        "status" => {
          summary: "show one-frame service and repo health",
          detail: ["/status", "Shows service state, git divergence, fix loop state, bundle status, and recent events."]
        },
        "resync" => {
          summary: "repair local divergence from origin/main",
          detail: ["/resync [--dry-run]", "Tags current HEAD, fetches, then resets and restarts unless dry-run is set."]
        },
        "tail" => {
          summary: "show recent event log lines",
          detail: ["/tail [N] [pattern]", "Filters runtime event JSONL by count and optional pattern."]
        },
        "why" => {
          summary: "explain a law, rule, anti-pattern, or style key",
          detail: ["/why <law|scan_rule|anti_pattern|style.key>"]
        },
        "propose" => {
          summary: "show next-action proposals",
          detail: ["/propose", "Ranks likely next actions from session, git, phase, and violation signals."]
        },
        "rules" => {
          summary: "list registered scan rules",
          detail: ["/rules list", "Shows rule IDs, severity, and implementation class."]
        },
        "triad" => {
          summary: "scan, preview fix, and review",
          detail: ["/triad <path>", "Runs scan, fix dry-run, and review for the same target."]
        },
        "rollback" => {
          summary: "revert the last recorded change",
          detail: ["/rollback", "Uses the undo stack; pipeline failure rollback remains automatic."]
        },
        "audit" => {
          summary: "show changed files this session",
          detail: ["/audit", "Lists git diff line counts for changed files."]
        },
        "grep" => {
          summary: "search session history",
          detail: ["/grep <pattern>", "Returns matching user/master turns from the current session."]
        },
        "watch" => {
          summary: "control background watching",
          detail: ["/watch on", "/watch off", "/watch status"]
        },
        "help" => {
          summary: "show command summaries or details",
          detail: ["/help", "/help <command>"]
        }
      }.freeze

      def build(infra:, ai:, root:)
        commands = {}
        commands.merge!(session_commands(infra))
        commands.merge!(mode_commands(infra[:config]))
        commands.merge!(memory_commands(infra[:memory], ai[:agent]))
        commands.merge!(work_commands(ai:, root:, infra:))
        commands.merge!(tool_commands(root, ai))
        commands.merge!(control_commands(ai[:standing], ai[:soul]))
        commands.merge!(system_commands(agent: ai[:agent], diag: infra[:diag], root:))
        commands["help"] = command(:help_text, nil)
        commands
      end

      def help_text(command = nil)
        key = command.to_s.strip.sub(/\A\//, "")
        return help_summary if key.empty?

        topic = HELP_TOPICS[key]
        return "help: unknown command /#{key}" unless topic

        (["/#{key} - #{topic[:summary]}"] + topic[:detail]).join("\n")
      end

      def help_summary
        lines = HELP_TOPICS.map { |cmd, topic| "/#{cmd} - #{topic[:summary]}" }
        (lines + ["/help <command> - show details"]).join("\n")
      end

      def session_commands(infra)
        session = infra[:session]
        undo = infra[:undo]
        logging = infra[:logging]
        config = infra[:config]
        {
          "clear" => command(:dispatch_clear, session),
          "save" => command(:dispatch_save, session),
          "history" => command(:dispatch_history, session),
          "grep" => command(:dispatch_grep, session),
          "audit" => command(:dispatch_audit, config),
          "tokens" => command(:dispatch_tokens, session),
          "cost" => command(:dispatch_cost, session),
          "undo" => command(:dispatch_undo, undo),
          "rollback" => command(:dispatch_rollback, undo),
          "redo" => command(:dispatch_redo, undo),
          "dmesg" => command(:dispatch_dmesg, logging),
          "config" => command(:dispatch_config, config)
        }
      end

      def mode_commands(config)
        reasoning_commands(config).merge(persona_commands(config)).merge(flag_commands(config))
      end

      def reasoning_commands(config)
        {
          "mode" => command(:dispatch_mode, config),
          "task" => command(:dispatch_task, config)
        }
      end

      def persona_commands(config)
        {
          "persona" => command(:dispatch_persona, config)
        }
      end

      def flag_commands(config)
        flags = %w[auto_review auto_lint auto_commit]
        flags.each_with_object({}) do |flag, h|
          h[flag] = command(:dispatch_flag, config, flag)
        end
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

      def dispatch_mode(config, ctx: nil)
        arg = arg_for(ctx)
        Master::Judge::Modes::SUPPORTED.include?(arg) ?
          (config["reasoning_mode"] = arg; config.save!; "mode: #{arg}") :
          "mode: #{config.reasoning_mode} (supported: #{Master::Judge::Modes::SUPPORTED.join(", ")})"
      end

      def dispatch_task(config, ctx: nil)
        arg = arg_for(ctx)
        arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}")
      end

      def dispatch_persona(config, ctx: nil)
        arg = arg_for(ctx)
        return "persona: #{config.persona}" if arg.empty?

        config["persona"] = arg
        config.save!
        "persona: #{arg}"
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
        out, status = Open3.capture2e("git", "-C", root, "diff", "--numstat", "HEAD")
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
          "soul" => command(:dispatch_soul, soul)
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
