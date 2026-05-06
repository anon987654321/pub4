# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class YamlQualityRule < Rule
        QUOTED_BOOL   = /:\s*["'](true|false|yes|no|null)["']/.freeze
        QUOTED_INT    = /:\s*["'](\d+)["']/.freeze
        UNNECESSARY_Q = /:\s*"([a-zA-Z0-9_\-\/\.]+)"/.freeze

        def initialize
          super
          @id          = "yaml_quality"
          @description = "YAML verbosity — unnecessary quotes, type coercions"
          @severity    = :style
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".yml") || path.end_with?(".yaml")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, 
message: "boolean/null as quoted string — remove quotes so YAML parses the type correctly") if line.match?(QUOTED_BOOL)
            findings << finding(line: num, 
message: "integer as quoted string — remove quotes") if line.match?(QUOTED_INT)
            findings << finding(line: num, 
message: "unnecessary quotes — plain scalars don't need quoting unless they contain : or #") if line.match?(UNNECESSARY_Q) && !line.match?(QUOTED_BOOL) && !line.match?(QUOTED_INT)
          end
          findings
        end
      end
    end
  end
end
