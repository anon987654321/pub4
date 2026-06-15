# frozen_string_literal: true

module Master
  module Now
    module Stages
      # Render — format the final output for display.
      class Render
        def initialize(renderer:)
          @renderer = renderer
        end

        def call(ctx)
          output = ctx.output
          rendered = case output
                     when Result::Ok
                       text = output.value!.to_s
                       text = Master::Voice::SoulDriftDetector.clean(text)
                       @renderer.render(text, mode: :plain)
                     when Result::Err then @renderer.render(output.message, mode: :error)
                     else
                       text = Master::Voice::SoulDriftDetector.clean(output.to_s)
                       @renderer.render(text, mode: :plain)
                     end

          Result.ok(ctx.merge(rendered:))
        end
      end
    end
  end
end
