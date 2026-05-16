# frozen_string_literal: true

require_relative "command_registry/agent_commands"
require_relative "command_registry/memory_commands"
require_relative "command_registry/service_commands"

module Master
  module Now
  # CommandRegistry — all pipeline-routable commands in one place.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        agent_commands(ai:, root:, infra:),
        memory_commands(infra[:memory], ai[:agent]),
        service_commands(ai, infra[:phase_gates], diag: infra[:diag], root: root),
        utility_commands(agent: ai[:agent], root:, cache: infra[:cache], code_index: infra[:code_index]),
        control_commands(ai[:standing], ai[:soul]),
"ecology" => ->(ctx) {
  scanner = Judge::RepoEcology.new(root:, event_bus: infra[:bus])
  path = ctx[:args].to_s.strip
  report = scanner.scan(path: path.empty? ? nil : path)
  scanner.render(report)
},
"brief"  => ->(_ctx) { dump_soul_files(root) },
"orient" => ->(_ctx) { dump_soul_files(root) },
"help" => ->(_ctx) {
          [
            "session: /save /clear /history [N] /tokens /undo /redo /exit",
            "scan: /run [path] /self-run /scan [profile] [path] /polish [path] /grind [N] /ecology [path]",
            "model: /model [id|list] /mode /persona /task",
            "memory: /mem /topic /rsi",
            "system: /diag [/section] /tree [N] /brief /guard [N] /reload /help"
          ].join("\n")
        }
      )
    end

    def session_commands(infra)
      session = infra[:session]
      undo = infra[:undo]
      logging = infra[:logging]
      config = infra[:config]
      {
        "clear"  => ->(_ctx) { session.clear!; "context cleared" },
        "save"   => ->(_ctx) { session.save!; "session saved" },
        "history" => ->(ctx) {
          n = ctx[:args].to_s.strip.to_i
          n = 10 if n <= 0
          recent = session.messages.last(n)
          next "history: empty" if recent.empty?
          recent.map { |m| "[#{m[:role]}] #{m[:content].to_s.gsub(/\s+/, ' ')[0, 120]}" }.join("\n")
        },
        "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
        "undo"   => ->(_ctx) { result = undo.undo!; result.ok? ? "reverted: #{result.value!}" : result.message },
        "redo"   => ->(_ctx) { result = undo.redo!; result.ok? ? "reapplied: #{result.value!}" : result.message },
        "dmesg"  => ->(_ctx) { logging.dmesg },
        "cost"   => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "config" => ->(_ctx) { config.data.inspect }
      }
    end

    SOUL_FILES = %w[soul rules ruby_style workflow standing_orders].freeze

    def dump_soul_files(root)
      SOUL_FILES.map { |name|
        rel  = "data/#{name}.yml"
        path = File.join(root, rel)
        "# #{rel}\n#{File.exist?(path) ? File.read(path) : "# missing"}"
      }.join("\n\n")
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
          arg   = ctx[:args].to_s.strip.to_sym
          names = Personality.persona_names
          if names.include?(arg)
            config["persona"] = arg.to_s; config.save!; "persona: #{arg}"
          else
            "persona: #{config["persona"] || "malay"} -- available: #{names.join(", ")}"
          end
        },
      }
    end

    def flag_commands(config)
      {
        "autotest" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then config["auto_testing"] = true;  config.save!; "autotest: on"
          when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
          else "autotest: #{config.auto_testing? ? "on" : "off"}"
          end
        }
      }
    end

  end
  end
end
