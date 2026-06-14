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
        session_commands(infra).merge(
          mode_commands(infra[:config]),
          memory_commands(infra[:memory], ai[:agent]),
          work_commands(ai:, root:, infra:),
          tool_commands(root, ai),
          control_commands(ai[:standing], ai[:soul]),
          system_commands(agent: ai[:agent], diag: infra[:diag], root:),
          "help" => ->(ctx) { help_text(ctx[:args].to_s.strip) }
        )
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
          "clear" => ->(_ctx) { session.clear!; "context cleared" },
          "save" => ->(_ctx) { session.save!; "session saved" },
          "history" => ->(ctx) {
            n = ctx[:args].to_s.strip.to_i
            n = 10 if n <= 0
            recent = session.messages.last(n)
            next "history: empty" if recent.empty?
            recent.map.with_index(1) { |m, i| Formatter.history_line(m, i) }.join("\n")
          },
          "grep" => ->(ctx) { grep_history(session, ctx[:args].to_s) },
          "audit" => ->(_ctx) { audit_changes(config["root"] || Dir.pwd) },
          "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
          "cost" => ->(_ctx) { Formatter.cost(session.cost) },
          "undo" => ->(_ctx) { r = undo.undo!; r.ok? ? "reverted: #{r.value!}" : r.message },
          "rollback" => ->(_ctx) { r = undo.undo!; r.ok? ? "rolled back: #{r.value!}" : r.message },
          "redo" => ->(_ctx) { r = undo.redo!; r.ok? ? "reapplied: #{r.value!}" : r.message },
          "dmesg" => ->(ctx) {
            n = ctx[:args].to_s.strip.to_i
            logging.dmesg(n.positive? ? n : Master::Trace::Logging::DEFAULT_DMESG_LINES)
          },
          "config" => ->(_ctx) { config.to_h.inspect }
        }
      end

      def mode_commands(config)
        reasoning_commands(config).merge(persona_commands(config)).merge(flag_commands(config))
      end

      def reasoning_commands(config)
        {
          "mode" => ->(ctx) {
            arg = ctx[:args].to_s.strip
            Master::Judge::Modes::SUPPORTED.include?(arg) ?
              (config["reasoning_mode"] = arg; config.save!; "mode: #{arg}") :
              "mode: #{config.reasoning_mode} (supported: #{Master::Judge::Modes::SUPPORTED.join(", ")})"
          },
          "task" => ->(ctx) {
            arg = ctx[:args].to_s.strip
            arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}")
          }
        }
      end

      def persona_commands(config)
        {
          "persona" => ->(ctx) {
            arg = ctx[:args].to_s.strip
            return "persona: #{config.persona}" if arg.empty?
            config["persona"] = arg; config.save!; "persona: #{arg}"
          }
        }
      end

      def flag_commands(config)
        flags = %w[auto_review auto_lint auto_commit]
        flags.each_with_object({}) do |flag, h|
          h[flag] = ->(ctx) {
            arg = ctx[:args].to_s.strip
            arg.empty? ? "#{flag}: #{config[flag]}" : (config[flag] = arg == "on"; config.save!; "#{flag}: #{config[flag]}")
          }
        end
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
          "orders" => cmd(:dispatch_orders, standing),
          "soul" => cmd(:dispatch_soul, soul)
        }
      end

      def dispatch_orders(standing, arg)
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

      def dispatch_soul(soul, arg)
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

      def arg_for(ctx) = ctx[:args].to_s.strip
      def expand_or_root(arg, root) = arg.empty? ? root : File.expand_path(arg, root)
      def cmd(method, *services) = ->(ctx) { send(method, *services, arg_for(ctx)) }
      def command(&block) = Command.new(&block)
    end
  end
end
