# frozen_string_literal: true

module Master3
  module Stages
    class Council
      def initialize(deliberation:, enabled: false)
        @deliberation = deliberation
        @enabled      = enabled
      end

      def call(ctx)
        return Result.ok(ctx) unless should_run?(ctx)

        output = extract_output(ctx)
        result = @deliberation.review(output, context: ctx[:message])
        return result if result.err?

        Result.ok(ctx.merge(council_feedback: result.value!))
      end

      def enable!  = (@enabled = true)
      def disable! = (@enabled = false)

      private

      def should_run?(ctx)
        return true if @enabled
        return true if dangerous_tool?(ctx)
        return true if multi_file_diff?(ctx)
        false
      end

      def dangerous_tool?(ctx)
        ctx[:last_tool_tier] == :dangerous
      end

      def multi_file_diff?(ctx)
        output = extract_output(ctx).to_s
        output.scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2
      end

      def extract_output(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then ""
        else out.to_s
        end
      end
    end
  end
end
