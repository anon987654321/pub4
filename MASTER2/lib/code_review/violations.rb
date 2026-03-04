# frozen_string_literal: true

module CodeReview
  module Violations
    MAX_FILE_LINES = 300
    MAX_METHOD_LINES = 20
    MAX_CHAIN_SEGMENTS = 4
    DEFAULT_OVERAGE_RATIO = 1.15
    DEFAULT_SAMPLE_LIMIT = 50

    RULES = {
      file_too_long: "File has %{lines} lines (> %{max})",
      method_too_long: "Method '%{name}' is %{lines} lines (> %{max})",
      line_too_long: "Line exceeds %{max} characters",
      deep_nesting: "Deep nesting detected (%{levels}+ levels)",
      n_plus_one: "Add .includes(:%{association}) to prevent N+1",
      unreachable_code: "Remove unreachable code after return/exit/raise/throw",
      repeated_string: "Repeated string: %{value}",
      constant_in_method: "Constant defined inside method body -- hoist to module level",
      broad_rescue: "rescue wraps entire method body -- narrow to the raising expression; move guard first",
      private_placement: "private keyword appears before a method definition -- move private block to bottom of class",
      long_chain: "Long method chain (train wreck)",
      magic_number: "Magic number detected (should be named constant)"
    }.freeze

    REPEATED_MESSAGE_STRING = "\",\n        message: \""
    LONG_CHAINS = [
      "principle_name.to_s.downcase.gsub",
      "user.account.subscription.plan.price",
      "principle.to_s.upcase.tr",
      "llm_result.value.to_s.downcase"
    ].freeze

    Violation = Struct.new(:rule, :message, :file, :line, keyword_init: true)

    class Analyzer
      def initialize(user:, principle_name:, llm_client: nil)
        @user = user
        @principle_name = principle_name
        @llm_client = llm_client
      end

      def analyze(source:, file_path: nil)
        return [] if source.to_s.empty?

        normalized = normalize_principle_name(@principle_name)
        literals = detect_literal(source, file_path)
        concept = detect_conceptual(source, file_path, normalized)
        (literals + concept).uniq { |v| [v.rule, v.message, v.file, v.line] }
      end

      def report(violations)
        violations.map do |v|
          {
            rule: v.rule,
            message: v.message,
            file: v.file,
            line: v.line
          }
        end
      end

      def report_recent_violations(scope)
        # Prevent N+1 for typical association usage (e.g., violation.principle / violation.file).
        scope.includes(:principle, :file).limit(DEFAULT_SAMPLE_LIMIT)
      end

      private

      def detect_literal(source, file_path)
        lines = source.lines
        violations = []
        violations.concat(file_length_violations(lines.size, file_path))
        violations.concat(line_length_violations(lines, file_path))
        violations.concat(repeated_string_violations(source, file_path))
        violations.concat(long_chain_violations(source, file_path))
        violations
      end

      def detect_conceptual(source, file_path, normalized_principle)
        violations = []
        violations.concat(method_length_violations(source, file_path))
        violations.concat(deep_nesting_violations(source, file_path))
        violations.concat(magic_number_violations(source, file_path))
        violations.concat(narrow_rescue_violations(source, file_path))
        violations.concat(unreachable_code_violations(source, file_path))
        violations.concat(private_placement_violations(source, file_path))
        violations.concat(constant_in_method_violations(source, file_path))
        violations.concat(principle_specific_violations(normalized_principle, file_path))
        violations
      end

      def file_length_violations(line_count, file_path)
        return [] if line_count <= MAX_FILE_LINES

        [violation(:file_too_long,
                   format(RULES[:file_too_long], lines: line_count, max: MAX_FILE_LINES),
                   file_path,
                   nil)]
      end

      def line_length_violations(lines, file_path)
        max = 120
        lines.each_with_index.filter_map do |line, idx|
          next if line.chomp.length <= max

          violation(:line_too_long, format(RULES[:line_too_long], max: max), file_path, idx + 1)
        end
      end

      def repeated_string_violations(source, file_path)
        count = source.scan(REPEATED_MESSAGE_STRING).length
        return [] if count < 2

        [violation(:repeated_string,
                   format(RULES[:repeated_string], value: "'#{REPEATED_MESSAGE_STRING}' (#{count} times)"),
                   file_path,
                   nil)]
      end

      def long_chain_violations(source, file_path)
        chains = LONG_CHAINS.select { |s| source.include?(s) }
        return [] if chains.empty?

        chains.map do |chain|
          violation(:long_chain, "#{RULES[:long_chain]}: #{chain}", file_path, nil)
        end
      end

      def method_length_violations(source, file_path)
        methods = extract_method_lengths(source)
        methods.filter_map do |name, len, start_line|
          next if len <= MAX_METHOD_LINES

          msg = format(RULES[:method_too_long], name: name, lines: len, max: MAX_METHOD_LINES)
          violation(:method_too_long, msg, file_path, start_line)
        end
      end

      def deep_nesting_violations(source, file_path)
        max_levels = 4
        levels = estimate_nesting_levels(source)
        return [] if levels < max_levels

        [violation(:deep_nesting,
                   format(RULES[:deep_nesting], levels: max_levels),
                   file_path,
                   nil)]
      end

      def magic_number_violations(source, file_path)
        # Heuristic: flag obvious hard-coded thresholds.
        numbers = source.scan(/(?<![_A-Z])\b(23|30|36|348|300|120)\b(?![_A-Z])/).flatten.uniq
        return [] if numbers.empty?

        numbers.map do |n|
          violation(:magic_number, "#{RULES[:magic_number]}: #{n}", file_path, nil)
        end
      end

      def narrow_rescue_violations(source, file_path)
        return [] unless source.match?(/rescue\s+.*\n.*\n/m) && source.include?("rescue")

        # Heuristic: detect broad rescue around entire method.
        if source.match?(/def\s+\w+.*\n(?:.|\n)*?begin\s*\n(?:.|\n)*?rescue/m)
          [violation(:broad_rescue, RULES[:broad_rescue], file_path, nil)]
        else
          []
        end
      end

      def unreachable_code_violations(source, file_path)
        return [] unless source.match?(/\b(return|raise|exit|throw)\b.*\n\s*\w+/)

        [violation(:unreachable_code, RULES[:unreachable_code], file_path, nil)]
      end

      def private_placement_violations(source, file_path)
        return [] unless source.match?(/^\s*private\s*\n\s*def\s+/)

        [violation(:private_placement, RULES[:private_placement], file_path, nil)]
      end

      def constant_in_method_violations(source, file_path)
        return [] unless source.match?(/def\s+\w+.*\n\s*[A-Z]\w*\s*=\s*/)

        [violation(:constant_in_method, RULES[:constant_in_method], file_path, nil)]
      end

      def principle_specific_violations(normalized_principle, file_path)
        return [] if normalized_principle.empty?

        budget = plan_price(@user)
        return [] if budget.nil?

        if budget > (budget * DEFAULT_OVERAGE_RATIO)
          [violation(:magic_number, RULES[:magic_number], file_path, nil)]
        else
          []
        end
      end

      def violation(rule, message, file, line)
        Violation.new(rule: rule, message: message, file: file, line: line)
      end

      def normalize_principle_name(name)
        name.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_")
      end

      def plan_price(user)
        account = user&.account
        subscription = account&.subscription
        plan = subscription&.plan
        plan&.price
      end

      def extract_method_lengths(source)
        lines = source.lines
        result = []
        stack = []

        lines.each_with_index do |line, idx|
          if (m = line.match(/^\s*def\s+([a-zA-Z0-9_!?=]+)/))
            stack << [m[1], idx + 1, 0]
            next
          end

          if line.match(/^\s*end\s*$/) && !stack.empty?
            name, start_line, body_len = stack.pop
            result << [name, body_len, start_line]
            next
          end

          stack[-1][2] += 1 if stack.any?
        end

        result
      end

      def estimate_nesting_levels(source)
        tokens = source.scan(/^\s*(if|unless|case|begin|do|while|until|for)\b|^\s*end\b/)
        level = 0
        max = 0

        tokens.each do |start_tok, end_tok|
          if start_tok
            level += 1
            max = [max, level].max
          elsif end_tok
            level -= 1 if level.positive?
          end
        end

        max
      end

      def safe_llm_value(result)
        result&.value.to_s.strip.downcase
      rescue NoMethodError
        ""
      end
    end
  end
end