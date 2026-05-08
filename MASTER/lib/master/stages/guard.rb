# frozen_string_literal: true

module Master
  module Stages
    class Guard
      def initialize(governor:, injection_guard:)
        @governor = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        return Result.err("injection detected", category: :validation) if @injection_guard && !@injection_guard.safe?(ctx[:user_message])

        Result.ok(ctx)
      end
    end
  end
end
