# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class TerseRule < Rule
        BOOL_CMP      = /(?:==|!=)\s*(?:true|false)\b/.freeze
        NIL_EQ        = /==\s*nil\b/.freeze
        NIL_NEQ       = /!=\s*nil\b/.freeze
        THEN_KWORD    = /\b(?:if|unless|when)\b[^#\n]*\bthen\b/.freeze
        SYMBOL_PROC   = /\.(map|select|reject|flat_map|filter_map|sort_by|min_by|max_by|count|sum|any\?|all\?|none\?|find)\s*\{\s*\|(\w+)\|\s*\2\.(\w+)\s*\}/.freeze
        NOT_EMPTY     = /!\s*\w+\.empty\?/.freeze

        def initialize
          super
          @id          = "terse"
          @description = "Verbose Ruby patterns — use idiomatic shortcuts"
          @severity    = :style
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            line_findings << finding(line: num, message: "== true/false is redundant — use the boolean directly") if line.match?(BOOL_CMP)
            line_findings << finding(line: num, message: "use .nil? instead of == nil") if line.match?(NIL_EQ)
            line_findings << finding(line: num, message: "use object instead of != nil — truthy check suffices") if line.match?(NIL_NEQ)
            line_findings << finding(line: num, message: "remove `then` — it is noise in multi-line if/unless") if line.match?(THEN_KWORD)
            line_findings << finding(line: num, message: "symbol-to-proc: .map(&:method_name) instead of block") if line.match?(SYMBOL_PROC)
            line_findings << finding(line: num, message: "!x.empty? → x.any?") if line.match?(NOT_EMPTY)
          end
          line_findings + redundant_returns(code)
        end

        private

        def redundant_returns(code)
          findings = []
          method_lines = []
          in_method = false
          depth = 0

          code.each_line.with_index(1) do |line, num|
            stripped = line.strip
            if !in_method && stripped.match?(/\bdef \w/)
              in_method = true
              method_lines = []
              depth = 1
              next
            end
            next unless in_method

            depth += stripped.scan(/\b(?:def|do|begin|if|unless|case|class|module)\b/).size
            depth -= stripped.scan(/\bend\b/).size

            if depth <= 0
              last = method_lines.reverse.find { |l| !l[:text].strip.empty? && !l[:text].strip.start_with?("#") }
              if last && last[:text].match?(/^\s*return\s+\S/) && !last[:text].match?(/return\s+.+\bif\b/)
                findings << finding(line: last[:num], message: "redundant return — last expression is the implicit return value")
              end
              in_method = false
              method_lines = []
              depth = 0
            else
              method_lines << { text: line, num: }
            end
          end
          findings
        end
      end
    end
  end
end
