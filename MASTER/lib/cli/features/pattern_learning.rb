# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module PatternLearning
        # Command pattern learning
        
        def initialize_pattern_learning
          @command_patterns = []
          @pattern_suggestions = {}
        end
        
        def learn_command_pattern(commands)
          return if commands.size < 2
          
          pattern = commands.map { |c| c.split.first }.join(' → ')
          @command_patterns << { pattern: pattern, timestamp: Time.now }
          
          # Keep last 100 patterns
          @command_patterns = @command_patterns.last(100)
          
          # Detect common sequences
          detect_common_sequences
        end
        
        def detect_common_sequences
          # Find patterns that repeat 3+ times
          pattern_counts = @command_patterns.map { |p| p[:pattern] }.tally
          
          @pattern_suggestions = pattern_counts.select { |_, count| count >= 3 }
                                               .transform_values { |count| count }
        end
        
        def suggest_next_command(current_cmd)
          # Look for patterns that start with current command
          recent = @command_patterns.last(10).map { |p| p[:pattern] }
          
          matching = recent.select { |p| p.start_with?(current_cmd) }
          return nil if matching.empty?
          
          # Extract next command from pattern
          pattern = matching.first
          parts = pattern.split(' → ')
          idx = parts.index(current_cmd)
          parts[idx + 1] if idx && idx < parts.size - 1
        end
        
        def show_learned_patterns
          return "No patterns learned yet" if @pattern_suggestions.empty?
          
          lines = ["#{C_BOLD}Common Command Patterns#{C_RESET}"]
          @pattern_suggestions.sort_by { |_, count| -count }.first(10).each do |pattern, count|
            lines << "  #{count}× #{pattern}"
          end
          
          lines.join("\n")
        end
      end
    end
  end
end
