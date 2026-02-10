# frozen_string_literal: true

module MASTER
  # SmartSuggest - Autonomous code refactoring suggestions
  # Analyzes code and proposes improvements through the Staging pipeline
  module SmartSuggest
    class << self
      def analyze(file_or_code, filename: nil)
        code = File.exist?(file_or_code.to_s) ? File.read(file_or_code) : file_or_code
        filename ||= File.basename(file_or_code.to_s)
        
        suggestions = []
        suggestions.concat(check_complexity(code, filename))
        suggestions.concat(check_duplication(code, filename))
        suggestions.concat(check_naming(code, filename))
        suggestions.concat(check_structure(code, filename))
        
        { file: filename, suggestions: suggestions, count: suggestions.size }
      end
      
      def analyze_directory(dir, extensions: %w[.rb])
        results = []
        Dir.glob(File.join(dir, "**", "*")).each do |file|
          next unless extensions.include?(File.extname(file))
          result = analyze(file)
          results << result if result[:count] > 0
        end
        results
      end
      
      def suggest_with_llm(code, filename: nil, tier: :fast)
        prompt = <<~PROMPT
          Analyze this Ruby code and suggest specific, actionable refactoring improvements.
          Focus on: DRY violations, KISS violations, dead code, naming, and structure.
          Return each suggestion with: location, category, description, and proposed fix.
          
          File: #{filename || 'unknown'}
          ```ruby
          #{code[0, 4000]}
          ```
        PROMPT
        
        LLM.ask(prompt, tier: tier)
      end
      
      private
      
      def check_complexity(code, filename)
        suggestions = []
        lines = code.lines
        
        # Long methods (>25 lines)
        current_method = nil
        method_start = 0
        depth = 0
        
        lines.each_with_index do |line, i|
          if line.match?(/^\s*def\s+\w/)
            current_method = line.strip
            method_start = i
            depth = 1
          elsif current_method
            depth += 1 if line.match?(/\b(do|if|unless|while|until|for|case|begin)\b/) && !line.match?(/\bend\b/)
            depth -= 1 if line.strip == "end"
            if depth <= 0
              method_length = i - method_start
              if method_length > 25
                suggestions << {
                  category: :complexity,
                  location: "#{filename}:#{method_start + 1}",
                  description: "Method '#{current_method.split('def ').last&.split('(')&.first}' is #{method_length} lines (max 25)",
                  severity: method_length > 50 ? :high : :medium
                }
              end
              current_method = nil
            end
          end
        end
        
        suggestions
      end
      
      def check_duplication(code, filename)
        suggestions = []
        lines = code.lines.map(&:strip).reject(&:empty?)
        
        # Find repeated blocks (3+ identical consecutive lines appearing 2+ times)
        (0..lines.size - 3).each do |i|
          block = lines[i, 3].join("\n")
          next if block.length < 20
          
          occurrences = 0
          (i + 3..lines.size - 3).each do |j|
            occurrences += 1 if lines[j, 3].join("\n") == block
          end
          
          if occurrences >= 1
            suggestions << {
              category: :duplication,
              location: "#{filename}:#{i + 1}",
              description: "Repeated code block found #{occurrences + 1} times — extract to method",
              severity: :medium
            }
          end
        end
        
        suggestions.uniq { |s| s[:description] }.first(3)
      end
      
      def check_naming(code, filename)
        suggestions = []
        
        # Single-letter variables (except i, j, k, e, f, m, n in blocks)
        code.scan(/(\b[a-z]\b)\s*=/).flatten.each do |var|
          next if %w[i j k e f m n x y _].include?(var)
          suggestions << {
            category: :naming,
            location: filename,
            description: "Single-letter variable '#{var}' — use descriptive name",
            severity: :low
          }
        end
        
        suggestions.first(3)
      end
      
      def check_structure(code, filename)
        suggestions = []
        
        total_lines = code.lines.size
        if total_lines > 300
          suggestions << {
            category: :structure,
            location: filename,
            description: "File is #{total_lines} lines — consider splitting (max 300)",
            severity: total_lines > 500 ? :high : :medium
          }
        end
        
        # Too many requires
        requires = code.scan(/^require/).size
        if requires > 15
          suggestions << {
            category: :structure,
            location: filename,
            description: "#{requires} require statements — this file may have too many responsibilities",
            severity: :medium
          }
        end
        
        suggestions
      end
    end
  end
end
