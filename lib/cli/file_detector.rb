module MASTER
  module CLI
    module FileDetector
      COMPLEXITY_THRESHOLDS = {
        lines: 200,
        methods: 10,
        branches: 20
      }

      def self.detect_type(file_path)
        return :unknown unless File.file?(file_path)

        case File.extname(file_path).downcase
        when '.rb'
          :ruby
        when '.py'
          :python
        when '.js', '.mjs'
          :javascript
        when '.ts'
          :typescript
        when '.java'
          :java
        else
          :unknown
        end
      end

      def self.analyze_complexity(file_path)
        return nil unless File.file?(file_path)

        content = File.read(file_path)
        lines = content.lines.count
        
        # Simple heuristics for complexity
        methods = content.scan(/\b(?:def|function|func)\s+\w+/).count
        branches = content.scan(/\b(?:if|else|elsif|case|when|switch)\b/).count

        {
          lines: lines,
          methods: methods,
          branches: branches,
          complex: lines > COMPLEXITY_THRESHOLDS[:lines] ||
                   methods > COMPLEXITY_THRESHOLDS[:methods] ||
                   branches > COMPLEXITY_THRESHOLDS[:branches]
        }
      end

      def self.suggest_command(file_path)
        type = detect_type(file_path)
        return nil if type == :unknown

        complexity = analyze_complexity(file_path)
        return nil unless complexity

        if complexity[:complex]
          { command: 'refactor', reason: 'File appears complex and could benefit from refactoring' }
        else
          { command: 'analyze', reason: 'File looks clean, analysis will provide insights' }
        end
      end
    end
  end
end
