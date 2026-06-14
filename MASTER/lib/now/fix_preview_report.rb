# frozen_string_literal: true

module Master
  module Now
    class FixPreviewReport
      def initialize(data)
        @data = data
      end

      def render
        return "preview: clean — no violations" if total.zero?

        ["preview: #{total} violations (no changes made)",
         "by rule:", *rule_lines,
         "top files:", *file_lines].join("\n")
      end

      private

      attr_reader :data

      def total
        data[:total]
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
