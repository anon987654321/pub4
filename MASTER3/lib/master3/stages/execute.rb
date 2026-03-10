# frozen_string_literal: true

module Master3
  module Stages
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        case handler
        when Proc, Method
          result = handler.call(ctx)
          Result.ok(ctx.merge(output: result))
        else
          result = handler.call(ctx)
          Result.ok(ctx.merge(output: result))
        end
      rescue => e
        Result.err("execute: #{e.message}", category: :unknown)
      end
    end
  end
end
