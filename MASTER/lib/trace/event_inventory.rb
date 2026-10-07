# frozen_string_literal: true

require "stringio"
require_relative "../../tools/event_bus_reach"

module Master
  module Trace
    module EventInventory
      module_function

      def report
        Operator::EventBusReach.report
      end

      def render(strict: false)
        io = StringIO.new
        code = Operator::EventBusReach.print_report(strict:, io:)
        [code, io.string]
      end
    end
  end
end
