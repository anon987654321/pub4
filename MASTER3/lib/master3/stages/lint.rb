# frozen_string_literal: true

module Master3
  module Stages
    class Lint
      def initialize(scanner:, config:)
        @scanner = scanner
        @config = config
      end

      def call(ctx)
        return Result.ok(ctx) unless @config.auto_testing?

        report = Quality::AutoTesting.new.run
        Result.ok(ctx.merge(lint_report: report))
      rescue => e
        Result.err("lint: #{e.message}", category: :unknown)
      end
    end
  end
end
