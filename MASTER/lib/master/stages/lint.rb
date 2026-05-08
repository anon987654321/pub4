# frozen_string_literal: true

module Master
  module Stages
    # Lint — scan written files and chat code blocks; autofix via autoloop if available.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil, root: nil, event_bus: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
        @root     = root
        @bus      = event_bus
      end

      def call(ctx)
        findings = []

        paths = Array(ctx[:written_files]).filter_map { |p| File.exist?(p) ? p : nil }
        paths.each do |scan_path|
          if File.directory?(scan_path)
            dir_map = Result.wrap(@scanner.scan_dir(scan_path, depth: :standard)).value_or({})
            findings.concat(dir_map.values.flat_map { |r| Result.wrap(r).value_or([]) })
          elsif scan_path.end_with?(".rb")
            findings.concat(Result.wrap(@scanner.scan(scan_path, depth: :standard)).value_or([]))
          end
        end

        output = ctx[:output].to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        if findings.any? && @autoloop
          fixable = findings.select { |f| !AutoLoop::SKIP_RULES.include?(f[:rule].to_s) }
          if fixable.any?
            fix_result = @autoloop.run(max_cycles: 3)
            ctx = ctx.merge(autofix_result: fix_result)
          end
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue StandardError => e
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          findings = Result.wrap(@scanner.scan(f.path, depth: :standard))
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
