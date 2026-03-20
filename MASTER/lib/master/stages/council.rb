# frozen_string_literal: true

module Master
  module Stages
    # Council — multi-perspective review of dangerous or significant output.
    # Fires automatically on dangerous requests, dangerous tools, or multi-file diffs.
    # Can also be enabled globally via config or `enable!`.
    class Council
      DANGEROUS_PATTERNS = [
        /\brm\s+-rf\b/i,
        /\bsudo\b/i,
        /\b(?:drop|truncate)\s+table\b/i,
        /\bchmod\s+777\b/i,
        /\b(?:delete|remove)\s+all\b/i,
      ].freeze

      def initialize(deliberation:, config: nil, enabled: false)
        @deliberation = deliberation
        @config       = config
        @enabled      = @config&.[]("council") == true || enabled
      end

      def call(ctx)
        return Result.ok(ctx) unless should_run?(ctx)

        payload = extract_payload(ctx)
        result  = @deliberation.review(payload, context: ctx[:message])
        return result if result.err?

        Result.ok(ctx.merge(council_feedback: result.value!))
      end

      def enable!
        @enabled = true
        @config&.[]=("council", true)
        @config&.save!
      end

      def disable!
        @enabled = false
        @config&.[]=("council", false)
        @config&.save!
      end

      def enabled? = @enabled

      private

      def should_run?(ctx)
        @enabled || dangerous_request?(ctx) || dangerous_tool?(ctx) || multi_file_diff?(ctx)
      end

      def dangerous_request?(ctx)
        msg = ctx[:message].to_s.gsub(/[[:cntrl:]]/, "")
        !msg.empty? && DANGEROUS_PATTERNS.any? { |p| msg.match?(p) }
      end

      def dangerous_tool?(ctx) = ctx[:last_tool_tier] == :dangerous

      def multi_file_diff?(ctx)
        # Council fires when output touches two or more distinct files.
        extract_payload(ctx).scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2
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
    end
  end
end
