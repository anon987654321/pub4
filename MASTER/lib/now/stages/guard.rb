# frozen_string_literal: true

module Master
  module Now
    module Stages
      # Guard — reject messages that contain prompt-injection patterns.
      # Skips scan when message is absent (command-only paths set no :message).
      class Guard
        SHELL_HINT = /\b(?:rm\s+-rf|curl\b.*\|\s*(?:bash|sh)\b|wget\b.*\|\s*(?:bash|sh)\b|mkfs|dd\s+if=)\b/i

        def initialize(governor:, injection_guard:)
          @governor = governor
          @injection_guard = injection_guard
        end

        def call(ctx)
          message_text = ctx.message.to_s
          return Result.ok(ctx) if message_text.empty?

          scan = @injection_guard.scan(message_text)
          return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

          tier_check = shell_tier_check(message_text)
          return tier_check if tier_check&.err?

          Result.ok(ctx)
        end

        private

        def shell_tier_check(message_text)
          return unless message_text.match?(SHELL_HINT) && @governor

          permit = @governor.permit?("guard:shell_hint", :dangerous, message_text[0, 120])
          return permit if permit.err?

          nil
        end
      end
    end
  end
end
