# frozen_string_literal: true

module Master
  module Stages
    class Lint
      def initialize(scanner:, config:)
        @scanner = scanner
        @config = config
      end

      def call(ctx)
        return Result.ok(ctx) unless @config.auto_testing?

        report = Quality::AutoTesting.new.run
        # Propagate failure; wrap bare error strings in Result::Err
        if report.respond_to?(:err?) && report.err?
          return report.respond_to?(:message) ? Result.err(report.message, category: :unknown) : Result.err("lint failed", category: :unknown)
        end

        Result.ok(ctx.merge(lint_report: report))
      rescue => e
        Result.err("lint: #{e.message}", category: :unknown)
      end
    end
  end
end
