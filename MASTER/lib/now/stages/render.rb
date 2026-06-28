# frozen_string_literal: true

module Master
  module Now
    module Stages
      # Render — format the final output for display.
      class Render
        def initialize(renderer:, output_check: nil, event_bus: nil)
          @renderer = renderer
          @output_check = output_check
          @bus = event_bus
        end

        def call(ctx)
          output = ctx.output
          rendered = case output
                     when Result::Ok  then @renderer.render(output.value!, mode: :plain)
                     when Result::Err then @renderer.render(output.message, mode: :error)
                     else                  @renderer.render(output.to_s, mode: :plain)
                     end

          findings = @output_check ? @output_check.check(rendered) : []
          publish_findings(findings, ctx)
          rendered = annotate(rendered, findings) if findings.any? { |finding| finding.severity == :error }

          Result.ok(ctx.merge(rendered:, output_findings: findings))
        end

        private

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
