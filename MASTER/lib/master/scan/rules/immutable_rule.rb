# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ImmutableRule — detects mutable shared state that violates IMMUTABLE.
      # Flags: unfrozen String/Array/Hash constants, attr_accessor on data objects,
      # class-level mutable variables (@@), and global variable mutations ($x =).
      class ImmutableRule < Rule
        UNFROZEN_CONST  = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*(?:"[^"]*"|'[^']*'|\[|\{)(?!.*\.freeze)/.freeze
        CLASS_VAR_WRITE = /^\s+@@\w+\s*=(?!=)/.freeze
        GLOBAL_WRITE    = /^\s+\$\w+\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "immutable"
          @description = "Mutable shared state — prefer frozen constants and immutable data flow"
          @severity    = :warning
          @axiom_tags  = [:IMMUTABLE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] if line.strip.start_with?("#")
            f = []
            f << finding(line: num, message: "unfrozen constant — append .freeze") if line.match?(UNFROZEN_CONST)
            f << finding(line: num, message: "class variable mutation (@@) — use instance state or inject") if line.match?(CLASS_VAR_WRITE)
            f << finding(line: num, message: "global variable mutation ($) — eliminate shared global state") if line.match?(GLOBAL_WRITE)
            f
          }
        end
      end
    end
  end
end
