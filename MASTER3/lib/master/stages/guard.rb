# frozen_string_literal: true

module Master
  module Stages
    class Guard
      def initialize(governor:, injection_guard:)
        @governor        = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        msg = ctx[:message].to_s
        unless msg.empty?
          scan = @injection_guard.scan(msg)
          return Result.err("guard: #{scan.message}", category: :validation) if scan.err?
        end
        Result.ok(ctx)
      end
    end
  end
end
