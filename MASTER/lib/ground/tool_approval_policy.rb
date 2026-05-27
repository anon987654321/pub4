# frozen_string_literal: true

module Master
  module Ground
  module ToolApprovalPolicy
    MODES = %i[plan ask act auto].freeze

    MODE_RULES = {
      plan: { writes: false, commands: :read_only, description: "read-only planning" },
      ask: { writes: :confirm, commands: :confirm_risky, description: "ask before mutation or risky command" },
      act: { writes: true, commands: :sandboxed, description: "act with sandbox policy" },
      auto: { writes: true, commands: :sandboxed, description: "safe autonomous execution with deny gates" }
    }.freeze

    module_function

    def normalize(mode)
      key = mode.to_s.downcase.to_sym
      MODES.include?(key) ? key : :ask
    end

    def allow_write?(mode, path: nil)
      rule = MODE_RULES.fetch(normalize(mode)).fetch(:writes)
      return true if rule == true
      return false if rule == false

      :confirm
    end

    def command_decision(mode, command)
      case MODE_RULES.fetch(normalize(mode)).fetch(:commands)
      when :read_only
        safe = SandboxPolicy.decide(command).allow?
        read_only = command.to_s.match?(/\A(?:git\s+(status|diff|log|show)|ls|find|grep|rg)\b/)
        safe && read_only ? :allow : :deny
      when :confirm_risky
        decision = SandboxPolicy.decide(command)
        decision.allow? ? :allow : (decision.deny? ? :deny : :ask)
      else
        decision = SandboxPolicy.decide(command)
        decision.mode
      end
    end

    def brief(mode = :ask)
      rule = MODE_RULES.fetch(normalize(mode))
      "Tool approval mode=#{normalize(mode)}: #{rule[:description]}."
    end
  end
  end
end
