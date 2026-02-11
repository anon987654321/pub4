# frozen_string_literal: true

module MASTER
  module Agents
    class RefactorAgent < BaseAgent
      def initialize(file_path:, target_principles: [], context: {})
        super(context)
        @file_path = file_path
        @target_principles = target_principles
        @original_code = File.read(file_path)
      end
      
      def execute
        # First, review the code
        review = CodeReviewAgent.new(
          file_path: @file_path,
          principles: @target_principles,
          context: @context
        ).execute_with_retry
        
        # Then refactor based on review
        refactored = generate_refactoring(review)
        
        # Validate refactoring
        validation = validate_refactoring(refactored, review)
        
        {
          original: @original_code,
          refactored: refactored[:code],
          diff: generate_diff(@original_code, refactored[:code]),
          improvements: refactored[:improvements],
          validation: validation,
          review: review
        }
      end
      
      private
      
      def generate_refactoring(review)
        principles_content = @target_principles.map do |p|
          skill = MASTER::SkillsIntegration.load_full(p)
          "#{skill[:name]}:\n#{skill[:content]}"
        end.join("\n\n")
        
        prompt = <<~PROMPT
          You are MASTER's refactoring agent.
          
          Original code review:
          Score: #{review[:score]}/100
          Violations: #{review[:violations]}
          
          Apply these principles to refactor the code:
          #{principles_content}
          
          Original code:
          ```ruby
          #{@original_code}
          ```
          
          Provide:
          
          REFACTORED_CODE:
          ```ruby
          [Complete refactored code]
          ```
          
          IMPROVEMENTS:
          [List of specific improvements made]
          
          BEFORE_AFTER_METRICS:
          [Complexity, lines of code, etc.]
        PROMPT
        
        response = call_llm(prompt, temperature: 0.2, max_tokens: 8000)
        
        {
          code: response[/REFACTORED_CODE:\s*```ruby\s*(.+?)\s*```/m, 1],
          improvements: response[/IMPROVEMENTS:\s*(.+?)(?=BEFORE_AFTER_METRICS:|$)/m, 1]&.strip,
          metrics: response[/BEFORE_AFTER_METRICS:\s*(.+?)$/m, 1]&.strip
        }
      end
      
      def validate_refactoring(refactored, review)
        require 'tempfile'
        
        # Re-review the refactored code
        temp_file = Tempfile.new(['refactored', '.rb'])
        temp_file.write(refactored[:code])
        temp_file.close
        
        new_review = CodeReviewAgent.new(
          file_path: temp_file.path,
          principles: @target_principles,
          context: @context
        ).execute_with_retry
        
        temp_file.unlink
        
        {
          score_improved: new_review[:score] > review[:score],
          original_score: review[:score],
          new_score: new_review[:score],
          remaining_violations: new_review[:violations]
        }
      end
      
      def generate_diff(original, refactored)
        begin
          require 'diffy'
          Diffy::Diff.new(original, refactored, context: 3).to_s(:color)
        rescue LoadError
          "# Install 'diffy' gem for diff support"
        end
      end
    end
  end
end