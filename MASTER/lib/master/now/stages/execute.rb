# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Execute — call the handler resolved by Route and store its output.
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        output = handler.call(ctx)
        return output if output.is_a?(Master::Result::Err)

        Result.ok(ctx.merge(output: output))
      rescue StandardError => e
        Result.err("execute: #{e.message}", category: :unknown)
      end
    end
  end
  end
end