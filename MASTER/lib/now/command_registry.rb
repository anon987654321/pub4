# frozen_string_literal: true

require_relative "command_registry/memory_commands"
require_relative "command_registry/work_commands"
require_relative "command_registry/system_commands"
require_relative "command_registry/tool_commands"

module Master
  module Now
    module CommandRegistry
      module_function

      def build(infra:, ai:, root:)
        session_commands(infra).merge(
          mode_commands(infra[:config]),
          memory_commands(infra[:memory], ai[:agent]),
          work_commands(ai:, root:, infra:),
          tool_commands(root, ai),
          control_commands(ai[:standing], ai[:soul]),
          system_commands(ai[:agent], infra[:diag], root),
          "help" => ->(_ctx) {
            [
              "unified: /run <natural language task>   # recommended for most work (intent inferred)",
              "scan:    /scan /self /fix [loop|preview|stop] /why /axioms /topic /propose-tree /ecology",
              "review:  /critique /review",
              "health:  /status /resync [--dry-run] /tail [N] [pattern]",
              "session: /save /clear /history /tokens /cost /undo /redo /checkpoint /dmesg /exit",
              "model:   /model /mode /persona /task",
              "memory:  /memory /dreams",
              "tools:   /postpro [args] /repligen [args] /photograph <prompt> /sing <lyrics>",
              "system:  /orient [topic] /tree /diff /commit /snapshot /diag /reload /help",
            ].join("\n"),
          }
        )
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
            recent.map { |m| "[#{m[:role]}] #{m[:content].to_s.gsub(/\s+/, " ")[0, 120]}" }.join("\n"),
          },
          "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
          "cost" => ->(_ctx) { "$#{"%.4f" % session.cost}" },
          "undo" => ->(_ctx) { r = undo.undo!; r.ok? ? "reverted: #{r.value!}" : r.message },
          "redo" => ->(_ctx) { r = undo.redo!; r.ok? ? "reapplied: #{r.value!}" : r.message },
          "dmesg" => ->(_ctx) { logging.dmesg },
          "config" => ->(_ctx) { config.to_h.inspect },
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
              "mode: #{config.reasoning_mode} (supported: #{Master::Judge::Modes::SUPPORTED.join(", ")})",
          },
          "task" => ->(ctx) {
            arg = ctx[:args].to_s.strip
            arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}"),
          },
        }
      end

      def persona_commands(config)
        {
          "persona" => ->(ctx) {
            arg = ctx[:args].to_s.strip
            return "persona: #{config.persona}" if arg.empty?,
          },
        }
      end

      def flag_commands(config)
        flags = %w[auto_review auto_lint auto_commit]
        flags.each_with_object({}) do |flag, h|
          h[flag] = ->(ctx) {
            arg = ctx[:args].to_s.strip
            arg.empty? ? "#{flag}: #{config[flag]}" : (config[flag] = arg == "on"; config.save!; "#{flag}: #{config[flag]}"),
          }
        end
      end

      def control_commands(standing, soul)
        {
          "orders" => cmd(:dispatch_orders, standing),
          "soul" => cmd(:dispatch_soul, soul),
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
    end
  end
end
