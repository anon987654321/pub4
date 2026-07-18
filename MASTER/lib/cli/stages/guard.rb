# frozen_string_literal: true

module Master
  module CLI
    module Stages
      # Guard — reject messages that contain prompt-injection patterns.
      # Skips scan when message is absent (command-only paths set no :message).
      class Guard
        SHELL_HINT = /\b(?:rm\s+-rf|curl\b.*\|\s*(?:bash|sh)\b|wget\b.*\|\s*(?:bash|sh)\b|mkfs|dd\s+if=)\b/i

        def initialize(governor:, injection_guard:, evidence: nil, event_bus: nil)
          @governor = governor
          @injection_guard = injection_guard
          @evidence = evidence
          @bus = event_bus
        end

        def call(ctx)
          message_text = ctx.message.to_s
          return Result.ok(ctx) if message_text.empty?

          scan = @injection_guard.scan(message_text)
          return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

          tier_check = shell_tier_check(message_text)
          return tier_check if tier_check&.err?

          evidence_check = verify_declared_evidence(ctx)
          return evidence_check if evidence_check&.err?

          Result.ok(ctx)
        end

        private

        def shell_tier_check(message_text)
          return unless message_text.match?(SHELL_HINT) && @governor

          permit = @governor.permit?("guard:shell_hint", :dangerous, message_text[0, 120])
          return permit if permit.err?

          nil
        end

        # Callers opt into a governed action through metadata because inferring
        # inferring a write from natural-language intent blocks safe planning turns.
        def verify_declared_evidence(ctx)
          return unless @evidence

          metadata = evidence_metadata(ctx)
          action = metadata_value(metadata, :evidence_action)
          return if action.to_s.empty? || !@evidence.required?(action)

          sources = metadata_value(metadata, :evidence_sources)
          result = @evidence.verify(action:, sources:)
          @bus&.publish("guard:evidence", action: action.to_s, accepted: result.ok?)
          result
        end

        def evidence_metadata(ctx)
          metadata = ctx.metadata
          metadata.respond_to?(:[]) ? metadata : {}
        end

        def metadata_value(metadata, key) = metadata[key] || metadata[key.to_s]
      end
    end
  end
end
