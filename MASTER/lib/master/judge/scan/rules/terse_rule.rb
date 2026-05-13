# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class TerseRule < Rule
        BOOL_CMP      = /(?:==|!=)\s*(?:true|false)\b/.freeze
        NIL_EQ        = /==\s*nil\b/.freeze
        NIL_NEQ       = /!=\s*nil\b/.freeze
        THEN_KWORD    = /\b(?:if|unless|when)\b[^#\n]*\bthen\b/.freeze
        SYMBOL_PROC   = /\.(map|select|reject|flat_map|filter_map|sort_by|min_by|max_by|count|sum|any\?|all\?|none\?|find)\s*\{\s*\|(\w+)\|\s*\2\.(\w+)\s*\}/.freeze
        NOT_EMPTY     = /!\s*\w+\.empty\?/.freeze
        LEN_ZERO      = /\.(length|size|count)\s*==\s*0\b/.freeze
        LEN_POS       = /\.(length|size|count)\s*(?:>|>=)\s*[01]\b/.freeze
        DOUBLE_BANG   = /!!\s*\w/.freeze
        UNLESS_NOT    = /\bunless\s+!/.freeze
        TERNARY_SELF  = /(\w+)\s*\?\s*\1\s*:/.freeze

        def initialize
          super
          @id          = "terse"
          @description = "Verbose Ruby patterns — use idiomatic shortcuts"
          @severity    = :style
          @rule_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            line_findings << finding(line: num, 
message: "== true/false is redundant — use the boolean directly") if line.match?(BOOL_CMP)
            line_findings << finding(line: num, message: "use .nil? instead of == nil") if line.match?(NIL_EQ)
            line_findings << finding(line: num, 
message: "use object instead of != nil — truthy check suffices") if line.match?(NIL_NEQ)
            line_findings << finding(line: num, 
message: "remove `then` — it is noise in multi-line if/unless") if line.match?(THEN_KWORD)
            line_findings << finding(line: num, 
message: "symbol-to-proc: .map(&:method_name) instead of block") if line.match?(SYMBOL_PROC)
            line_findings << finding(line: num, message: "!x.empty? → x.any?") if line.match?(NOT_EMPTY)
            line_findings << finding(line: num, message: ".length/size/count == 0 → .empty?") if line.match?(LEN_ZERO)
            line_findings << finding(line: num, message: ".length/size/count > 0 → .any?") if line.match?(LEN_POS)
            line_findings << finding(line: num, 
message: "!! is a no-op on booleans and obscures intent — use explicit truthiness") if line.match?(DOUBLE_BANG)
            line_findings << finding(line: num, message: "unless !x → if x") if line.match?(UNLESS_NOT)
            line_findings << finding(line: num, message: "x ? x : y → x || y") if line.match?(TERNARY_SELF)
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
                findings << finding(line: last[:num], 
message: "redundant return — last expression is the implicit return value")
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
end
