# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Guard — reject messages that contain prompt-injection patterns.
    # Skips scan when message is absent (command-only paths set no :message).
    class Guard
      def initialize(governor:, injection_guard:)
        @governor = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        message_text = ctx.message.to_s
        return Result.ok(ctx) if message_text.empty?

        scan = @injection_guard.scan(message_text)
        return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

        Result.ok(ctx)
      end
    end
  end
  end
end
