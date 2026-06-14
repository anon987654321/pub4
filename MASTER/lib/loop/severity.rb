# frozen_string_literal: true

module Master
  module Loop
    module Severity
      module_function

      def at_least?(severity, minimum)
        rank(severity) >= rank(minimum)
      end

      def rank(severity)
        Master::SEVERITY_RANK[severity.to_sym] || 0
      rescue StandardError
        0
      end
    end
  end
end
