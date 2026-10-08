# frozen_string_literal: true

module Master
  module CLI
    module Stages
      # Render — format the final output for display.
      class Render
        def initialize(renderer:, output_check: nil, output_guard: nil, event_bus: nil)
          @renderer = renderer
          @output_check = output_check
          @output_guard = output_guard
          @bus = event_bus
        end

        def call(ctx)
          output = ctx.output
          mode = output.is_a?(Result::Err) ? :error : :plain
          text = case output
                 when Result::Ok  then output.value!
                 when Result::Err then output.message
                 else                  output.to_s
                 end
          rendered = @renderer.render(text, mode:)
          # A presenter is allowed to transform output, never erase it. An empty
          # render of non-empty source made /doctor, /fix and other commands look
          # as though Enter did nothing. Preserve the source as the deterministic
          # fallback; display_result can then diagnose a genuinely empty turn.
          rendered = text.to_s if rendered.to_s.empty? && !text.to_s.empty?

          findings = @output_check ? @output_check.check(rendered) : []
          findings += guard_findings(rendered, mode)
          publish_findings(findings, ctx)

          Result.ok(ctx.merge(rendered:, output_findings: findings))
        end

        private

        # The evidence contract reaches the reply here rather than in
        # Voice::Renderer, because this is the funnel for the assistant's final
        # answer and Renderer#render also carries prompts, dim status lines and
        # the thinking indicator, none of which claim anything. The posture is
        # warn: the issue is appended as a finding and published, and the reply
        # is still delivered. Refusing would drop MASTER's answer to punish its
        # phrasing, which reads to the operator as a hang and loses the content
        # a person could have judged for themselves.
        def guard_findings(rendered, mode)
          return [] unless @output_guard

          result = @output_guard.validate(rendered, context: @renderer.output_context(mode),
                                                    writes: Trace::WriteTracker.current&.paths)
          return [] if result.ok?

          result.message.split("; ").map do |issue|
            Review::OutputCheck::Finding.new(category: "evidence_contract", pattern: issue,
                                             line: 1, severity: :error, excerpt: issue)
          end
        end

        def publish_findings(findings, ctx)
          return if findings.empty?

          @bus&.publish(
            "output:findings",
            turn_id: ctx.turn_id,
            findings: findings.map(&:to_h),
          )
        end

      end
    end
  end
end
