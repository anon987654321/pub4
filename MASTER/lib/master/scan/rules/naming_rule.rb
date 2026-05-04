# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class NamingRule < Rule
        IS_PREFIX      = /def is_\w+(?!\?)/.freeze
        GET_PREFIX     = /def get_\w+/.freeze
        SET_PREFIX     = /def set_\w+/.freeze
        BOOL_NO_QMARK  = /def (?:has|can|should|will|did|was|have)_\w+(?!\?)/.freeze
        SCREAMING_ABBR = /\b[A-Z]{4,}\b/.freeze

        def initialize
          super
          @id          = "naming"
          @description = "Method names violate Ruby conventions"
          @severity    = :style
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "is_ prefix: use adjective with ? suffix (e.g. valid? not is_valid?)") if line.match?(IS_PREFIX)
            findings << finding(line: num, message: "get_ prefix: Ruby readers drop get_ (e.g. name not get_name)") if line.match?(GET_PREFIX)
            findings << finding(line: num, message: "set_ prefix: use name= for writers (e.g. name= not set_name)") if line.match?(SET_PREFIX)
            findings << finding(line: num, message: "boolean predicate missing ? suffix — add ? to indicate it returns bool") if line.match?(BOOL_NO_QMARK)
          end
          findings
        end
      end
    end
  end
end
