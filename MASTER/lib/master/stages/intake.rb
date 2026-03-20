# frozen_string_literal: true

module Master
  module Stages
    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string.
      COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m

      def call(ctx)
        msg = ctx[:user_message].to_s.strip
        return Result.err("intake: empty message", category: :validation) if msg.empty?

        if (m = msg.match(COMMAND_RE))
          Result.ok(ctx.merge(intent: :command, command: m[1], args: m[2].strip))
        else
          Result.ok(ctx.merge(intent: :llm, message: msg))
        end
      end
    end
  end
end
