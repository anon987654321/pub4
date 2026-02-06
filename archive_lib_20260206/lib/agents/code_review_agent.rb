# frozen_string_literal: true

module MASTER
  module Agents
    class CodeReviewAgent < BaseAgent
      def initialize(file_path:, principles: [], context: {})
        super(context)
        @file_path = file_path
        @principles = principles
        @code = File.read(file_path)
      end
      
      def execute
        # Load principle skills
        loaded_principles = @principles.map do |p|
          MASTER::SkillsIntegration.load_full(p)
        end
        
        prompt = build_review_prompt(loaded_principles)
        response = call_llm(prompt, temperature: 0.3)
        
        parse_review(response)
      end
      
      private
      
      def build_review_prompt(principles)
        <<~PROMPT
          You are MASTER's code review agent (v#{MASTER::VERSION}).
          
          Review this code against these principles:
          #{principles.map { |p| "- #{p[:name]}: #{p[:description]}" }.join("\n")}
          
          File: #{@file_path}
          
          ```ruby
          #{@code}
          ```
          
          Provide a structured review:
          
          OVERALL_SCORE: [0-100]
          
          VIOLATIONS:
          [List each principle violation with line numbers]
          
          STRENGTHS:
          [What the code does well]
          
          REFACTORING_SUGGESTIONS:
          [Specific improvements with code examples]
          
          COMPLEXITY_ANALYSIS:
          [Cyclomatic complexity, nesting depth, etc.]
        PROMPT
      end
      
      def parse_review(response)
        {
          file: @file_path,
          score: response[/OVERALL_SCORE:\s*(\d+)/, 1]&.to_i || 0,
          violations: extract_section(response, 'VIOLATIONS'),
          strengths: extract_section(response, 'STRENGTHS'),
          suggestions: extract_section(response, 'REFACTORING_SUGGESTIONS'),
          complexity: extract_section(response, 'COMPLEXITY_ANALYSIS'),
          raw_response: response
        }
      end
      
      def extract_section(text, section_name)
        pattern = /#{section_name}:\s*(.+?)(?=\n[A-Z_]+:|$)/m
        text[pattern, 1]&.strip
      end
    end
  end
end