# frozen_string_literal: true

module Master
  module Ground
    # Runs low-cost data and constitutional integrity checks during construction.
    module BootChecks
      StrictFailure = Class.new(StandardError)
      module_function

      def run(root:, event_bus: nil)
        check_schema(root:, event_bus:)
        check_immutability(root:, event_bus:) unless ENV["MASTER_SKIP_IMMUTABILITY"] == "1"
        check_self(root:, event_bus:) if ENV["MASTER_SELFCHECK"] == "quick"
        Result.ok(:clean)
      end

      def check_schema(root:, event_bus:)
        result = SchemaCheck.verify!(root:)
        report(result.message, event_bus:) if result.err?
      end

      def check_immutability(root:, event_bus:)
        result = Immutability.verify!(root:)
        event_bus&.publish("boot:immutability", status: result.value!)
      rescue Immutability::Violation => e
        report(e.message, event_bus:)
      end

      def check_self(root:, event_bus:)
        self_report = Master::Loop::SelfCheck.new(root:).quick
        report(self_report.summary, event_bus:) unless self_report.clean?
      end

      def report(message, event_bus:)
        event_bus&.publish("boot:integrity_error", message:)
        raise StrictFailure, message if ENV["MASTER_STRICT"] == "1"

        warn(message)
      end
    end
  end
end
