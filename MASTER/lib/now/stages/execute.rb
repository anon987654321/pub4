# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Execute — call the handler resolved by Route and store its output.
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        raw = handler.call(ctx)
        return raw if raw.is_a?(Master::Result::Err)

        output = raw.is_a?(Master::Result) ? raw.value!.to_s : raw.to_s
        Result.ok(ctx.merge(output: output))
      rescue StandardError => e
        Result.err("execute: #{e.message}", category: :unknown)
      end
    end
  end
  end
end