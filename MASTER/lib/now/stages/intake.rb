# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string (may be empty)
      COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m.freeze

      def call(ctx)
        Master::Now::PipelineContext.validate!(ctx)
        raw = ctx.user_message
        message_text = raw.to_s.strip
        return Result.err("intake: empty message", category: :validation) if message_text.empty?

        if (m = message_text.match(COMMAND_RE))
          command = m[1].downcase
          args    = m[2].strip
          args = nil if args.empty?
          Result.ok(ctx.merge(intent: :command, command: command, args: args))
        else
          Result.ok(ctx.merge(intent: :llm, message: message_text))
        end
      end
    end
  end
  end
end
