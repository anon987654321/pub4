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

          findings = @output_check ? @output_check.check(rendered) : []
          findings += guard_findings(rendered, mode)
          publish_findings(findings, ctx)
          rendered = annotate(rendered, findings) if findings.any? { |finding| finding.severity == :error }

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

          result = @output_guard.validate(rendered, context: @renderer.output_context(mode))
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

        def annotate(rendered, findings)
          categories = findings.select { |finding| finding.severity == :error }.map(&:category).uniq
          "#{rendered}\n\n#{@renderer.render("output warning: #{categories.join(', ')}", mode: :warning)}"
        end
      end
    end
  end
end
