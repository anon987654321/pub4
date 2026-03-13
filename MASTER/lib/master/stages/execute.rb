# frozen_string_literal: true

module Master
  module Stages
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        result = handler.call(ctx)
        Result.ok(ctx.merge(output: result))
      rescue => e
        Result.err("execute: #{e.message}", category: :unknown)
      end
    end
  end
end
