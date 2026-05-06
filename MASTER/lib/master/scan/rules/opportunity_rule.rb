# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Opportunities are not violations — they are structural improvements waiting to happen.
      # Detects: deep nesting (reflow), lambda dispatch tables (regroup into Command),
      # thin delegation wrappers (collapse), and dense inline hashes (extract class).
      # Severity :info so they show up in deep scans without polluting standard output.
      class OpportunityRule < Rule
        NESTING_THRESHOLD   = 4
        HASH_PAIR_THRESHOLD = 4
        LAMBDA_TABLE_MIN    = 3
        INDENT_UNIT         = 2

        def initialize
          super
          @id          = "opportunity"
          @description = "Structural improvement opportunity — refactor for clarity or cohesion"
          @severity    = :info
          @axiom_tags  = %i[SIMPLEST_WORKS DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          findings += deep_nesting(code)
          findings += lambda_dispatch_table(code)
          findings += thin_delegation(code)
          findings += dense_inline_hash(code)
          findings
        end

        private

        def deep_nesting(code)
          results    = []
          base_indent = nil
          method_line = nil

          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#") || stripped.start_with?(".")
            indent = 0
            indent += 1 while line[indent] == " "
            if stripped.start_with?("def ")
              base_indent = indent
              method_line = number
            elsif base_indent && stripped == "end"
              base_indent = nil
              method_line = nil
            elsif base_indent
              relative_depth = (indent - base_indent) / INDENT_UNIT
              if relative_depth >= NESTING_THRESHOLD
                results << finding(line: method_line,
                  message: "#{relative_depth} levels of nesting in method — reflow with early returns or extract method")
                base_indent = nil
              end
            end
          end
          results
        end

        def lambda_dispatch_table(code)
          results = []
          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            next unless stripped.start_with?('"') && stripped.include?("=>") && stripped.include?("->")
            count = code.lines.count { |other|
 other.strip.start_with?('"') && other.strip.include?("=>") && other.strip.include?("->") }
            if count >= LAMBDA_TABLE_MIN
              results << finding(line: number,
                message: "lambda dispatch table (#{count} entries) — regroup into Command objects or a registry")
              break
            end
          end
          results
        end

        def thin_delegation(code)
          results = []
          lines   = code.lines
          lines.each_with_index do |line, line_index|
            stripped = line.strip
            next unless stripped.start_with?("def ") && !stripped.include?("=")
            method_name = stripped.split(" ", 3)[1].to_s.split("(", 2).first
            body_index  = line_index + 1
            next if body_index >= lines.size
            body    = lines[body_index].strip
            closing = lines[body_index + 1]&.strip
            next unless body.include?(".") && !body.start_with?("#") && closing == "end"
            delegated = body.split(".").last.split("(").first.strip
            if delegated == method_name
              results << finding(line: line_index + 1,
                message: "#{method_name}: thin transparent delegation — use Forwardable or delegate")
            end
          end
          results
        end

        def dense_inline_hash(code)
          results = []
          in_method  = false
          method_line = 0
          hash_pairs  = 0

          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            if stripped.start_with?("def ")
              in_method   = true
              method_line = number
              hash_pairs  = 0
            elsif stripped == "end" && in_method
              if hash_pairs >= HASH_PAIR_THRESHOLD
                results << finding(line: method_line,
                  message: "#{hash_pairs} hash pairs inline — hoist to a named constant or extract a builder")
              end
              in_method  = false
              hash_pairs = 0
            elsif in_method
              hash_pairs += stripped.scan("=>").size
            end
          end
          results
        end
      end
    end
  end
end
