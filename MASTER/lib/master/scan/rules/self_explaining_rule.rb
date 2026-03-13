# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SelfExplainingRule — detects names that obscure intent, violating SELF_EXPLAINING.
      # Flags method/variable names that are abbreviations, noise words, or too generic
      # to reveal purpose without reading the implementation.
      class SelfExplainingRule < Rule
        NOISE_NAMES  = /\b(do_it|handle|process|run_it|execute_it|go|doit)\b/.freeze
        ABBREV_METHOD = /^\s+def\s+(tmp|res|ret|val|obj|thingy|stuff|thing|data2?|info2?)\b/.freeze
        ABBREV_VAR    = /\b(tmp|res|ret|val|obj|arr|lst|hsh|idx|cnt|num|str)\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "self_explaining"
          @description = "Opaque names — names should reveal purpose without reading the implementation"
          @severity    = :warning
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] if line.strip.start_with?("#")
            f = []
            f << finding(line: num, message: "noise method name — rename to reveal intent") if line.match?(NOISE_NAMES)
            f << finding(line: num, message: "abbreviated method name — use the full descriptive word") if line.match?(ABBREV_METHOD)
            f << finding(line: num, message: "abbreviated variable — prefer descriptive identifier") if line.match?(ABBREV_VAR)
            f
          }
        end
      end
    end
  end
end
