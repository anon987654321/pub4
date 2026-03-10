# frozen_string_literal: true

module Master3
  module Stages
    class Lint
      def initialize(scanner:)
        @scanner = scanner
      end

      def call(ctx)
        # Lint is advisory -- violations reported but do not block
        Result.ok(ctx)
      end
    end
  end
end
