# frozen_string_literal: true

module Master
  module CLI
    class FixPreviewReport
      def initialize(data)
        @data = data
      end

      def render
        return ["preview: clean — no violations", *skipped_line].join("\n") if total.to_i.zero?

        ["preview: #{total} violations (no changes made)",
         *skipped_line,
         "by rule:", *rule_lines,
         "top files:", *file_lines].join("\n")
      end

      private

      attr_reader :data

      def total
        data[:total]
      end

      # Named, because a fix pass that narrows its own input without saying so
      # reads as a smaller problem rather than a smaller scope.
      def skipped_line
        count = data[:skipped].to_i
        return [] if count.zero?

        ["skipped: #{count} generated/vendored file(s) — not fixable in place"]
      end

      def rule_lines
        data[:rules].map { |rule, count| "  #{rule.ljust(28)} #{count}" }
      end

      def file_lines
        data[:files].map { |file, count| "  #{file[0, 60].ljust(60)} #{count}" }
      end
    end
  end
end
