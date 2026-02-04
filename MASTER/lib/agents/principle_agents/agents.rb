# frozen_string_literal: true
require_relative "base"

module Master
  module Agents
    module PrincipleAgents
      class DRYAgent < Base
        def initialize(llm: nil)
          super(principle: "PRINCIPLE_DRY", llm: llm)
        end
        
        def scan(files)
          violations = []
          
          files.each do |file|
            next unless File.exist?(file)
            next unless file.end_with?(".rb")
            
            content = File.read(file)
            duplicates = find_duplicates(content)
            
            duplicates.each do |dup|
              violations << {
                file: file,
                line: dup[:line],
                principle: @principle,
                description: "Duplicate code found (#{dup[:occurrences]} occurrences)",
                context: dup
              }
            end
          end
          
          violations
        end
        
        def suggest_refactor(violation)
          prompt = <<~PROMPT
            Extract this duplicate code into a reusable method:
            
            File: #{violation[:file]}
            Code pattern: #{violation[:context][:pattern]}
            Occurrences: #{violation[:context][:occurrences]}
            
            Provide:
            1. New method name
            2. Method definition
            3. How to call it
            
            Format:
            METHOD_NAME: method_name
            DEFINITION:
            ```ruby
            def method_name
              # code
            end
            ```
            USAGE: method_name(args)
          PROMPT
          
          result = @llm.ask(prompt, tier: :code)
          return result unless result.ok?
          
          # Parse LLM response
          response = result.value
          method_name = response[/METHOD_NAME:\s*(.+)/i, 1]&.strip
          definition = response[/DEFINITION:\s*```ruby\n(.*?)```/mi, 1]&.strip
          usage = response[/USAGE:\s*(.+)/i, 1]&.strip
          
          Result.ok({
            type: :extract,
            description: "Extract to method: #{method_name}",
            new_code: definition,
            call_code: usage,
            old_code: violation[:context][:pattern],
            update_calls: true
          })
        end
        
        private
        
        def find_duplicates(content)
          duplicates = []
          lines = content.lines
          
          # Simple duplicate detection: look for repeated 3+ line blocks
          (0...lines.size - 2).each do |i|
            block = lines[i, 3].join
            next if block.strip.empty?
            next if block.strip.start_with?("#") # Skip comments
            
            # Count occurrences
            occurrences = content.scan(Regexp.escape(block)).size
            
            if occurrences > 1
              duplicates << {
                line: i + 1,
                pattern: block.strip,
                occurrences: occurrences
              }
            end
          end
          
          # Remove overlapping duplicates
          duplicates.uniq { |d| d[:pattern] }
        end
      end
      
      class SOLIDSRPAgent < Base
        def initialize(llm: nil)
          super(principle: "SOLID_SRP", llm: llm)
        end
        
        def scan(files)
          violations = []
          
          files.each do |file|
            next unless File.exist?(file)
            next unless file.end_with?(".rb")
            
            content = File.read(file)
            
            # Detect god classes (many methods, long files)
            if god_class?(content)
              violations << {
                file: file,
                line: 1,
                principle: @principle,
                description: "God class: #{method_count(content)} methods, #{content.lines.size} lines",
                context: { methods: method_count(content), lines: content.lines.size }
              }
            end
          end
          
          violations
        end
        
        def suggest_refactor(violation)
          # Use LLM to suggest how to split the class
          Result.ok({
            type: :extract,
            description: "Split class into smaller, focused classes"
          })
        end
        
        private
        
        def god_class?(content)
          method_count(content) > 10 || content.lines.size > 300
        end
        
        def method_count(content)
          content.scan(/^\s*def\s+/).size
        end
      end
      
      class KISSAgent < Base
        def initialize(llm: nil)
          super(principle: "PRINCIPLE_KISS", llm: llm)
        end
        
        def scan(files)
          violations = []
          
          files.each do |file|
            next unless File.exist?(file)
            next unless file.end_with?(".rb")
            
            content = File.read(file)
            lines = content.lines
            
            # Detect complex methods (high cyclomatic complexity)
            lines.each_with_index do |line, i|
              if line =~ /^\s*def\s+/
                # Simple heuristic: count conditionals in next 20 lines
                method_lines = lines[i, 20]
                complexity = method_lines.join.scan(/\b(if|unless|case|while|until|rescue)\b/).size
                
                if complexity > 5
                  violations << {
                    file: file,
                    line: i + 1,
                    principle: @principle,
                    description: "Complex method (#{complexity} conditionals)",
                    context: { complexity: complexity }
                  }
                end
              end
            end
          end
          
          violations
        end
        
        def suggest_refactor(violation)
          Result.ok({
            type: :extract,
            description: "Simplify method: extract conditionals, reduce nesting"
          })
        end
      end
      
      class PerformanceAgent < Base
        def initialize(llm: nil)
          super(principle: "PRINCIPLE_PERFORMANCE", llm: llm)
        end
        
        def scan(files)
          violations = []
          
          files.each do |file|
            next unless File.exist?(file)
            next unless file.end_with?(".rb")
            
            content = File.read(file)
            
            # Detect N+1 queries
            if content =~ /\.each\s+do.*?\.(find|where)/m
              violations << {
                file: file,
                line: content[0..$~.begin(0)].lines.size,
                principle: @principle,
                description: "Potential N+1 query detected",
                context: { pattern: "each + query" }
              }
            end
          end
          
          violations
        end
        
        def suggest_refactor(violation)
          Result.ok({
            type: :replace,
            description: "Use eager loading or batch queries"
          })
        end
      end
    end
  end
end
