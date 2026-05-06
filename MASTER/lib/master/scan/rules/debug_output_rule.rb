# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DebugOutputRule < Rule
        PP_CALL     = /^\s*pp?\s+(?!self\b)/.freeze
        STDERR_PUTS = /\$stderr\.puts\b/.freeze
        BINDING_PRY = /\bbinding\.pry\b/.freeze
        DEBUGGER    = /\bdebugger\b/.freeze

        def initialize
          super
          @id          = "debug_output"
          @description = "Debug output left in lib/ — remove before shipping"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb") && path.include?("/lib/")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, 
message: "p/pp debug call — remove or publish via event bus") if line.match?(PP_CALL)
            findings << finding(line: num, 
message: "$stderr.puts — use @bus.publish or $stdout for structured output") if line.match?(STDERR_PUTS)
            findings << finding(line: num, 
message: "binding.pry left in — remove before commit") if line.match?(BINDING_PRY)
            findings << finding(line: num, message: "debugger left in — remove before commit") if line.match?(DEBUGGER)
          end
          findings
        end
      end
    end
  end
end
