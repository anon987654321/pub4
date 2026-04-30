# frozen_string_literal: true

module Master
  module Stages
    # Lint — always runs. Scans written files AND code blocks in chat output.
    # Violations are collected; if autofix is possible, feeds them back to
    # the autoloop for correction.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil, root: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
        @root     = root
      end

      def call(ctx)
        findings = []

        # 1. Scan any files that were written during Execute
        paths = Array(ctx[:written_files]).filter_map { |p| File.exist?(p) ? p : nil }
                paths.each do |scan_path|
          next unless File.exist?(scan_path)
          if File.directory?(scan_path)
            result = @scanner.scan_dir(scan_path, depth: :standard)
            findings.concat(result.value!.flat_map { |_, r| r.respond_to?(:ok?) && r.ok? ? r.value! : [] }) if result.respond_to?(:ok?) && result.ok?
          elsif scan_path.end_with?(".rb")
            result = @scanner.scan(scan_path, depth: :standard)
            findings.concat(result.value!) if result.respond_to?(:ok?) && result.ok?
          end
        end

        # 2. Scan code blocks embedded in chat output
        output = ctx[:output].to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        # 3. Autofix if violations found and autoloop available
        if findings.any? && @autoloop
          fixable = findings.select { |f| !AutoLoop::SKIP_RULES.include?(f[:rule].to_s) }
          if fixable.any?
            fix_result = @autoloop.run(max_cycles: 3)
            ctx = ctx.merge(autofix_result: fix_result)
          end
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue => e
        # Lint failure must not block the pipeline
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      # Scan a code string without writing to disk.
      # Creates a tempfile, scans it, deletes it.
      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          result = @scanner.scan(f.path, depth: :quick)
          if result.respond_to?(:ok?) && result.ok?
            findings = result.value!.map { |v| v.merge(source: :inline) }
          end
        end
        findings
      rescue StandardError => e
        @bus&.publish("lint:scan_error", error: e.message)
        []
      end
    end
  end
end
