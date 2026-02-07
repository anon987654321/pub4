module MASTER
  class Engine
    def initialize
      @llm = LLM.new
      @parser = Parser.new
    end
    
    def refactor(code, path)
      language = detect_language(path)
      ast = @parser.parse(code, language)
      
      suggestions = @llm.analyze_code(code, language)
      
      if autonomous_decision?(suggestions)
        apply_refactoring(code, suggestions)
      else
        { success: false, error: "Manual review required" }
      end
    end
    
    def analyze(code, path)
      language = detect_language(path)
      suggestions = @llm.analyze_code(code, language)
      
      {
        language: language,
        suggestions: suggestions,
        complexity: calculate_complexity(code)
      }
    end
    
    def execute(command)
      # REPL command execution
      case command
      when /^analyze (.+)/
        analyze_file($1)
      when /^refactor (.+)/
        refactor_file($1)
      else
        "Unknown command: #{command}"
      end
    end
    
    private
    
    def detect_language(path)
      case File.extname(path)
      when '.rb' then 'ruby'
      when '.py' then 'python'
      when '.js' then 'javascript'
      when '.go' then 'go'
      else 'unknown'
      end
    end
    
    def autonomous_decision?(suggestions)
      # Simple heuristic: apply if all suggestions are low-risk
      suggestions.all? { |s| s[:risk] == 'low' }
    end
    
    def apply_refactoring(code, suggestions)
      # Apply transformations
      refactored = code.dup
      
      suggestions.each do |suggestion|
        if suggestion[:type] == 'replace'
          refactored.gsub!(suggestion[:from], suggestion[:to])
        end
      end
      
      { success: true, code: refactored }
    end
    
    def calculate_complexity(code)
      # Basic complexity metric
      lines = code.lines.count
      case lines
      when 0..50 then 'low'
      when 51..200 then 'medium'
      else 'high'
      end
    end
  end
end
