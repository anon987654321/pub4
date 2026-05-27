# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Lint — scan written files and chat code blocks; autofix via autoloop if available.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, root: nil, event_bus: nil, **_)
        @scanner = scanner
        @config  = config
        @root    = root
        @bus     = event_bus
      end

      def call(ctx)
        findings = []

        paths = Array(ctx.written_files).filter_map { |p| File.exist?(p) ? p : nil }
        paths.each do |scan_path|
          if File.directory?(scan_path)
            dir_map = Result.wrap(@scanner.scan_dir(scan_path, depth: :deep)).value_or({})
            findings.concat(dir_map.values.flat_map { |r| Result.wrap(r).value_or([]) })
          elsif scan_path.end_with?(".rb")
            findings.concat(Result.wrap(@scanner.scan(scan_path, depth: :deep)).value_or([]))
          end
        end

        output = ctx.output.to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Lint.call", event_bus: @bus)
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          findings = Result.wrap(@scanner.scan(f.path, depth: :deep))
            .value_or([]).map { |v| v.merge(source: :inline) }
        end
        findings
      rescue StandardError => e
        @bus&.publish("lint:scan_error", error: e.message)
        []
      end
    end
  end
  end
end
