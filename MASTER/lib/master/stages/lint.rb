# frozen_string_literal: true

module Master
  module Stages
    # Lint — run static analysis after execution when auto-testing is enabled.
    # Uses the shared scanner so rules are consistent with sweep/autoloop.
    class Lint
      def initialize(scanner:, config:)
        @scanner = scanner
        @config  = config
      end

      def call(ctx)
        return Result.ok(ctx) unless @config.auto_testing?

        root   = ctx[:path].to_s
        root   = Master::ROOT if root.empty?
        report = @scanner.scan_dir(root, depth: :standard)

        return Result.err(report.message, category: :unknown) if report.respond_to?(:err?) && report.err?

        Result.ok(ctx.merge(lint_report: report))
      rescue => e
        Result.err("lint: #{e.message}", category: :unknown)
      end
    end
  end
end
