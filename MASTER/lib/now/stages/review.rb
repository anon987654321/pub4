# frozen_string_literal: true

require_relative "../../judge/verdict"

module Master
  module Now
    module Stages
      # Review — one post-execution pass for council feedback, lint, and pruning.
      class Review
        def initialize(council:, scanner:, config:, root: nil, event_bus: nil, **_)
          @council = council
          @lint = Lint.new(scanner:, config:, root:, event_bus:)
          @prune = Prune.new
          @bus = event_bus
        end

        def call(ctx)
          ctx = run_council(ctx)
          ctx = run_stage(@lint, ctx).value_or(ctx)
          publish_verdict(ctx)
          run_stage(@prune, ctx)
        rescue StandardError => e
          @bus&.publish("review:error", message: e.message)
          Result.ok(ctx.merge(review_error: e.message))
        end

        private

        def run_council(ctx)
          return ctx unless @council

          group = Master::Now::Pipeline::ParallelGroup.new(@council, bus: @bus)
          run_stage(group, ctx).value_or(ctx)
        end

        def run_stage(stage, ctx)
          result = stage.call(ctx)
          return result if result.respond_to?(:ok?) && !result.ok?

          Result.wrap(result).map { |value| value || ctx }
        rescue StandardError => e
          @bus&.publish("review:stage_error", stage: stage.class.name, message: e.message)
          Result.ok(ctx)
        end

        # Hybrid-Norm verdict: deterministic lint signal + council rubric, published (non-blocking).
        def publish_verdict(ctx)
          rubric = council_confidence(ctx)
          errors = lint_errors(ctx)
          return if rubric.nil? && errors.nil?

          verdict = Master::Judge::Verdict.new.call(deterministic: { lint: (errors || 0).zero? }, rubric_score: rubric || 0.5)
          @bus&.publish("review:verdict", pass: verdict.pass?, score: verdict.score, reasons: verdict.reasons)
        rescue StandardError => e
          @bus&.publish("review:verdict_error", message: e.message)
        end

        def council_confidence(ctx)
          scores = Array(ctx.council_feedback).filter_map { |item| item[:confidence] if item.respond_to?(:[]) }
          scores.empty? ? nil : scores.sum.to_f / scores.size
        rescue StandardError
          nil
        end

        def lint_errors(ctx)
          Array(ctx.lint_report).count { |finding| finding.respond_to?(:severity) && finding.severity.to_s == "error" }
        rescue StandardError
          nil
        end
      end
    end
  end
end
