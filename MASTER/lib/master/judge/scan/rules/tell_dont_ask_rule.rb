# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Querying an object's state then acting on it from outside breaks encapsulation.
      # The decision should live inside the object (tell it what to do, don't ask what it is).
      # Flags the most common Ruby patterns: .status/.state/.type == then method call,
      # and nil? guards that should be moved into the object.
      class TellDontAskRule < Rule
        STATE_QUERY  = /\b(\w+)\.(status|state|type|kind|mode|phase)\s*==/.freeze
        NIL_GUARD    = /\b(\w+)\.nil\?\s*\|\|/.freeze
        READY_QUERY  = /\b(\w+)\.ready\?\s*&&\s*\1\./.freeze

        def initialize
          super
          @id          = "tell_dont_ask"
          @description = "Tell-Don't-Ask: move state-based decisions into the object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num,
              message: "TDA: querying .status/.state outside the object — move the decision into the class") if line.match?(STATE_QUERY)
            findings << finding(line: num,
              message: "TDA: nil? guard before method call — use Null Object or move nil check into the object") if line.match?(NIL_GUARD)
            findings << finding(line: num,
              message: "TDA: ready? check then method call on same object — replace with a single command method") if line.match?(READY_QUERY)
          end
          findings
        end
      end
    end
  end
  end
end
