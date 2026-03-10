# frozen_string_literal: true

module Master3
  module Stages
    class Intake
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
