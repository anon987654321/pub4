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

        payload = extract_payload(ctx)
        result = @deliberation.review(payload, context: ctx[:message])
        return result if result.err?

        Result.ok(ctx.merge(council_feedback: result.value!))
      end

      def enable!  = (@enabled = true)
      def disable! = (@enabled = false)
      def enabled? = @enabled

      private

      def should_run?(ctx)
        return true if @enabled
        return true if dangerous_request?(ctx)
        return true if dangerous_tool?(ctx)
        return true if multi_file_diff?(ctx)
        false
      end

      def dangerous_request?(ctx)
        msg = ctx[:message].to_s
        # Strip control characters before logging to prevent log injection
        safe_msg = msg.gsub(/[[:cntrl:]]/, "")
        return false if safe_msg.empty?

        patterns = [
          /\brm\s+-rf\b/i,
          /\bsudo\b/i,
          /\b(drop|truncate)\s+table\b/i,
          /\bchmod\s+777\b/i,
          /\b(delete|remove)\s+all\b/i
        ]

        patterns.any? { |pattern| safe_msg.match?(pattern) }
      end

      def dangerous_tool?(ctx)
        ctx[:last_tool_tier] == :dangerous
      end

      def multi_file_diff?(ctx)
        output = extract_output(ctx).to_s
        output.scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2
      end

      def extract_payload(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then ""
        else
          text = out.to_s
          text.empty? ? ctx[:message].to_s : text
        end
      end

      alias extract_output extract_payload
    end
  end
end
