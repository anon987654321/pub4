# frozen_string_literal: true

module MASTER
  # LLMFriendly - Guidelines for writing code that LLMs can easily understand
  # Learned from analyzing what causes confusion during AI-assisted development
  module LLMFriendly
    GUIDELINES = {
      # Structure
      single_entry_point: "One master.rb that requires everything in order",
      explicit_dependencies: "Don't assume modules exist - check with defined?()",
      consistent_patterns: "Pick one style (extend self vs class << self) and use it everywhere",
      
      # Naming
      descriptive_names: "method_that_does_this() not do_it()",
      no_abbreviations: "configuration not cfg, response not resp",
      verb_noun_methods: "save_session(), load_config(), validate_input()",
      
      # Documentation
      module_purpose: "First line after module should be # comment explaining purpose",
      method_contracts: "Document what goes in, what comes out, what can fail",
      example_usage: "Show how to call it, not just what it does",
      
      # Data flow
      explicit_returns: "Return Result.ok/err, not mixed types",
      immutable_preference: "Prefer .merge() over mutation",
      symbolize_always: "JSON.parse with symbolize_names: true, always",
      
      # Testing
      behavior_names: "test_guard_blocks_dangerous_commands not test_guard_1",
      isolated_tests: "Each test sets up its own state, no shared mutable state",
      
      # File organization  
      max_300_lines: "Split large files - easier to fit in context window",
      group_related: "Keep related code together, even if it makes file longer",
      config_in_one_place: "All constants in config.rb or data/*.yml",
    }.freeze

    # Score a file for LLM-friendliness
    def self.score(code)
      points = 0
      max = 10

      # Has frozen_string_literal
      points += 1 if code.match?(/^# frozen_string_literal: true/)
      
      # Has module docstring
      points += 1 if code.match?(/module \w+\n\s+# [A-Z]/)
      
      # Uses Result monad
      points += 1 if code.match?(/Result\.(ok|err)/)
      
      # No bare rescue
      points += 1 unless code.match?(/rescue\s*$/)
      
      # Uses guard clauses
      points += 1 if code.match?(/return .* (if|unless) /)
      
      # Under 300 lines
      points += 1 if code.lines.size <= 300
      
      # Has examples in comments
      points += 1 if code.match?(/#.*example:|#.*usage:/i)
      
      # Consistent style (all extend self OR all class << self)
      extend_count = code.scan(/extend self/).size
      class_self_count = code.scan(/class << self/).size
      points += 1 if extend_count == 0 || class_self_count == 0
      
      # No magic numbers
      points += 1 unless code.match?(/[^0-9\.]\d{3,}[^0-9]/) # 3+ digit numbers
      
      # Descriptive method names (at least 8 chars average)
      methods = code.scan(/def (\w+)/).flatten
      avg_len = methods.empty? ? 10 : methods.sum(&:length).to_f / methods.size
      points += 1 if avg_len >= 8

      { score: points, max: max, percent: (points.to_f / max * 100).round }
    end

    # Suggest improvements
    def self.suggest(code)
      suggestions = []
      
      unless code.match?(/^# frozen_string_literal: true/)
        suggestions << "Add frozen_string_literal pragma at top"
      end
      
      unless code.match?(/module \w+\n\s+# [A-Z]/)
        suggestions << "Add module docstring: # ModuleName - What it does"
      end
      
      if code.match?(/rescue\s*$/)
        suggestions << "Change bare 'rescue' to 'rescue StandardError'"
      end
      
      if code.lines.size > 300
        suggestions << "File is #{code.lines.size} lines - consider splitting"
      end
      
      suggestions
    end
  end
end
