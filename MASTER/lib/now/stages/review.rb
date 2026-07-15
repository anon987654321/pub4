# frozen_string_literal: true

require_relative "../destructive_routes"
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
          ctx = merge_written_files(ctx)
          ctx = run_council(ctx)
          ctx = run_stage(@lint, ctx).value_or(ctx)
          verdict_result = publish_verdict(ctx)
          return verdict_result if verdict_result.err?

          run_stage(@prune, verdict_result.value!)
        rescue StandardError => e
          @bus&.publish("review:error", message: e.message)
          Result.ok(ctx.merge(review_error: e.message))
        end

        private

        def merge_written_files(ctx)
          tracker = Master::Trace::WriteTracker.current
          return ctx unless tracker

          merged = (Array(ctx.written_files) + tracker.paths).uniq
          return ctx if merged.empty? || merged == Array(ctx.written_files)

          ctx.merge(written_files: merged)
        end

        def run_council(ctx)
          return ctx unless @council

          group = Master::Now::Pipeline::ParallelGroup.new(@council, bus: @bus)
          run_stage(group, ctx).value_or(ctx)
        end

        def run_stage(stage, ctx)
          result = stage.call(ctx)
          return result if result.is_a?(Result) && result.err?

          wrapped = result.is_a?(Result) ? result : Result.ok(result)
          wrapped.map { |value| value || ctx }
        rescue StandardError => e
          @bus&.publish("review:stage_error", stage: stage.class.name, message: e.message)
          Result.ok(ctx)
        end

        # Hybrid-Norm verdict: lint + council rubric; blocks destructive routes when configured.
        def publish_verdict(ctx)
          rubric = council_confidence(ctx)
          errors = lint_errors(ctx)
          return Result.ok(ctx) if rubric.nil? && errors.nil?

          verdict = build_and_publish_verdict(ctx, rubric, errors)
          merged = ctx.merge(review_verdict: verdict.pass?)
          return Result.ok(merged) unless blocking_destructive?(ctx) && !verdict.pass?

          @bus&.publish("review:blocked", command: ctx.command, reasons: verdict.reasons, phase: "post_execute")
          Result.err("review: blocked — #{verdict.reasons.join(", ")}", category: :policy)
        rescue StandardError => e
          @bus&.publish("review:verdict_error", message: e.message)
          Result.ok(ctx)
        end

        def build_and_publish_verdict(ctx, rubric, errors)
          verdict = Master::Judge::Verdict.new.call(
            deterministic: { lint: (errors || 0).zero? },
            rubric_score: rubric || 0.5
          )
          @bus&.publish(
            "review:verdict",
            pass: verdict.pass?,
            score: verdict.score,
            reasons: verdict.reasons,
            command: ctx.command,
            phase: "post_execute"
          )
          verdict
        end

        def blocking_destructive?(ctx)
          DestructiveRoutes.blocking_review? && DestructiveRoutes.destructive_route?(ctx)
        end

        def council_confidence(ctx)
          scores = Array(ctx.council_feedback).filter_map { |item| item[:confidence] if item.respond_to?(:[]) }
          scores.empty? ? nil : scores.sum.to_f / scores.size
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Review.council_confidence")
          nil
        end

        def lint_errors(ctx)
          Array(ctx.lint_report).count { |finding| finding.respond_to?(:severity) && finding.severity.to_s == "error" }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Review.lint_errors")
          nil
        end
      end
    end
  end
end
