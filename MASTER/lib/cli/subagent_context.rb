# frozen_string_literal: true

module Master
  module CLI
    # Fiber-local tool boundary for typed child agents (opencrabs pattern #5).
    module SubagentContext
      module_function

      MAX_DEPTH = 2

      def run(type:, allowed:, &block)
        prev_type = Fiber[:subagent_type]
        prev_allowed = Fiber[:subagent_allowed]
        prev_depth = Fiber[:subagent_depth].to_i
        depth = prev_depth + 1
        if depth > MAX_DEPTH
          raise Master::SecurityError, "subagent nesting depth #{depth} exceeds #{MAX_DEPTH}"
        end

        Fiber[:subagent_type] = type
        Fiber[:subagent_allowed] = allowed
        Fiber[:subagent_depth] = depth
        block.call
      ensure
        Fiber[:subagent_type] = prev_type
        Fiber[:subagent_allowed] = prev_allowed
        Fiber[:subagent_depth] = prev_depth
      end

      def active_type = Fiber[:subagent_type]

      def restricted? = !Fiber[:subagent_allowed].nil?

      # The bounds this fiber runs under, for the prompt; nil outside a child.
      def brief
        return unless restricted?

        Ground::Policy::Subagent.brief(active_type, Fiber[:subagent_allowed])
      end

      def permits?(tool_name)
        allowed = Fiber[:subagent_allowed]
        return true if allowed.nil?

        name = tool_name.to_s
        allowed.include?(name)
      end

      def depth = Fiber[:subagent_depth].to_i
    end
  end
end
