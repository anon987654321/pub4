# frozen_string_literal: true

module Master
  module Ground
    # Fiber-local tool boundary for typed child agents (opencrabs pattern #5).
    module SubagentContext
      module_function

      def run(type:, allowed:, &block)
        prev_type = Fiber[:subagent_type]
        prev_allowed = Fiber[:subagent_allowed]
        Fiber[:subagent_type] = type
        Fiber[:subagent_allowed] = allowed
        block.call
      ensure
        Fiber[:subagent_type] = prev_type
        Fiber[:subagent_allowed] = prev_allowed
      end

      def active_type = Fiber[:subagent_type]

      def restricted? = !Fiber[:subagent_allowed].nil?

      def permits?(tool_name)
        allowed = Fiber[:subagent_allowed]
        return true if allowed.nil?

        name = tool_name.to_s
        allowed.include?(name)
      end
    end
  end
end