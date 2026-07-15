# frozen_string_literal: true

require_relative "../destructive_routes"
require_relative "../../judge/verdict"

module Master
  module Now
    module Stages
      # DestructiveReview — pre-execute council gate for destructive slash commands.
      class DestructiveReview
        def initialize(deliberation:, event_bus: nil, **_)
          @deliberation = deliberation
          @bus = event_bus
        end

        def call(ctx)
          return Result.ok(ctx) unless pre_execute?(ctx)

          payload = "/#{ctx.command} #{ctx.args}".strip
          result = @deliberation.review(payload, context: ctx.user_message)
          return result if result.err?

          feedback = result.value!
          veto = check_council_veto(ctx, feedback)
          return veto if veto

          verdict = build_verdict(feedback)
          publish_verdict(ctx, verdict, phase: "pre_execute")
          blocked = check_verdict_pass(ctx, verdict)
          return blocked if blocked

          Result.ok(ctx.merge(council_feedback: feedback, review_preapproved: true))
        rescue StandardError => e
          @bus&.publish("review:error", message: e.message, phase: "pre_execute")
          Result.ok(ctx.merge(review_error: e.message))
        end

        private

        def check_council_veto(ctx, feedback)
          return nil unless council_veto?(feedback)

          publish_blocked(ctx, "council_veto")
          Result.err("review: blocked destructive /#{ctx.command}", category: :policy)
        end

        def check_verdict_pass(ctx, verdict)
          return nil if verdict.pass?

          publish_blocked(ctx, verdict.reasons.join(", "))
          Result.err("review: blocked destructive /#{ctx.command} — #{verdict.reasons.join(", ")}", category: :policy)
        end

        def pre_execute?(ctx)
          ctx.intent == :command &&
            ctx.destructive_route == true &&
            DestructiveRoutes.blocking_review?
        end

        def council_veto?(feedback)
          text = feedback.to_s.downcase
          text.scan(/\b(?:reject|block|veto)\b/).size >= 3
        end

        def build_verdict(feedback)
          scores = Array(feedback).filter_map { |item| item[:confidence] if item.respond_to?(:[]) }
          rubric = scores.empty? ? 0.55 : scores.sum.to_f / scores.size
          Master::Judge::Verdict.new.call(deterministic: { council: true }, rubric_score: rubric)
        end

        def publish_verdict(ctx, verdict, phase:)
          @bus&.publish(
            "review:verdict",
            pass: verdict.pass?,
            score: verdict.score,
            reasons: verdict.reasons,
            command: ctx.command,
            phase: phase
          )
        end

        def publish_blocked(ctx, reason)
          @bus&.publish("review:blocked", command: ctx.command, reason: reason, phase: "pre_execute")
        end
      end
    end
  end
end
