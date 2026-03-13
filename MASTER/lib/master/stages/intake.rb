# frozen_string_literal: true

module Master
  module Stages
    class Intake
      # Group [2] (args) is used; group [1] (command name) is used.
      # The trailing `(?:.*)` captures the rest of the line but the group is non-capturing
      # because we access args via m[2] (the second capturing group: `(.*)`).
      # Note: COMMAND_RE keeps two capturing groups — m[1]=command, m[2]=args.
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
