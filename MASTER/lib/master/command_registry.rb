# frozen_string_literal: true

require_relative "command_registry/agent_commands"
require_relative "command_registry/memory_commands"
require_relative "command_registry/service_commands"

module Master
  # CommandRegistry — all pipeline-routable commands in one place.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        agent_commands(ai:, root:, infra:),
        memory_commands(infra[:memory], ai[:agent]),
        service_commands(ai),
        utility_commands(ai[:agent], root, infra[:cache]),
        control_commands(ai[:standing], ai[:soul]),
        "help" => ->(_ctx) {
          "just talk. intent is inferred automatically.\n" \
          "exit with /exit or ctrl-C twice."
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
        "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
        "undo"   => ->(_ctx) { result = undo.undo!; result.ok? ? "reverted: #{result.value!}" : result.message },
        "dmesg"  => ->(_ctx) { logging.dmesg },
        "cost"   => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "config" => ->(_ctx) { config.data.inspect }
      }
    end

    def mode_commands(config)
      {
        "mode" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if Reasoning::Modes::SUPPORTED.include?(arg)
            config["reasoning_mode"] = arg
            config.save!
            "mode: #{arg}"
          else
            "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
          end
        },
        "task" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            "task_type: #{config.task_type}"
          else
            config["task_type"] = arg
            config.save!
            "task_type: #{arg}"
          end
        },
        "autotest" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "on"  then config["auto_testing"] = true; config.save!; "autotest: on"
          when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
          else "autotest: #{config.auto_testing? ? "on" : "off"}"
          end
        },
        "persona" => ->(ctx) {
          arg = ctx[:args].to_s.strip.to_sym
          names = Personality::PERSONAS.keys
          if names.include?(arg)
            config["persona"] = arg.to_s
            config.save!
            "persona: #{arg}"
          else
            "persona: #{config["persona"] || "dark_malay"} -- available: #{names.join(", ")}"
          end
        }
      }
    end

  end
end
