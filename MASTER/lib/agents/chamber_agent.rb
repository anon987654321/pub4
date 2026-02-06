# frozen_string_literal: true

module MASTER
  module Agents
    class ChamberAgent < BaseAgent
      # Chamber configuration
      CHAMBER_MODELS = {
        strategist: "gpt-4o",
        analyst: "claude-3.5-sonnet",
        critic: "gpt-4o-mini",
        synthesizer: "claude-3.7-sonnet"
      }
      
      VOTING_THRESHOLD = 0.66 # 66% consensus required
      MAX_ROUNDS = 3
      
      def initialize(question:, context: {})
        super(context)
        @question = question
        @rounds = []
        @consensus_reached = false
      end
      
      def execute
        puts "chamber: #{CHAMBER_MODELS.keys.size} roles, #{MAX_ROUNDS} rounds max"
        
        MAX_ROUNDS.times do |round_num|
          puts "  round #{round_num + 1}/#{MAX_ROUNDS}"
          
          round_result = execute_round(round_num)
          @rounds << round_result
          
          if consensus_reached?(round_result)
            @consensus_reached = true
            return synthesize_final_answer(round_result)
          end
        end
        
        # No consensus reached - synthesizer makes final call
        puts "  no consensus, synthesizing..."
        synthesize_final_answer(@rounds.last)
      end
      
      private
      
      def execute_round(round_num)
        previous_arguments = round_num > 0 ? format_previous_round(@rounds.last) : nil
        
        responses = {}
        
        # Each model provides their perspective in parallel
        threads = CHAMBER_MODELS.map do |role, model|
          Thread.new do
            prompt = build_prompt(role, previous_arguments)
            response = call_llm(prompt, model: model, temperature: 0.7)
            
            parsed = parse_response(response)
            
            [role, {
              model: model,
              response: response,
              answer: parsed[:answer],
              reasoning: parsed[:reasoning],
              confidence: parsed[:confidence]
            }]
          end
        end
        
        # Wait for all responses
        threads.each { |t| responses.merge!(t.value.to_h) }
        
        # Display responses
        display_round_responses(responses)
        
        responses
      end
      
      def build_prompt(role, previous_arguments)
        base_prompt = <<~PROMPT
          You are the #{role.to_s.upcase} in MASTER's Chamber deliberation system.
          
          Your role:
          #{role_description(role)}
          
          Question: #{@question}
          
          Context:
          #{format_context}
        PROMPT
        
        if previous_arguments
          base_prompt += <<~PROMPT
            Previous Round Arguments:
            #{previous_arguments}
            
            Consider these arguments and refine your position.
          PROMPT
        end
        
        base_prompt + <<~PROMPT
          
          Provide your response in this format:
          
          ANSWER: [Your clear, concise answer]
          
          REASONING:
          [Your detailed reasoning, citing evidence]
          
          CONFIDENCE: [0.0-1.0]
          
          CONCERNS:
          [Any concerns or caveats]
        PROMPT
      end
      
      def role_description(role)
        {
          strategist: "Focus on long-term implications, strategic fit, and alignment with goals. Consider the big picture.",
          analyst: "Provide data-driven analysis. Break down the problem systematically. Focus on facts and evidence.",
          critic: "Challenge assumptions. Identify risks, edge cases, and potential failures. Play devil's advocate.",
          synthesizer: "Consider all perspectives. Find common ground. Propose balanced solutions."
        }[role]
      end
      
      def format_context
        @context.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
      
      def format_previous_round(round)
        round.map do |role, data|
          <<~ARG
            #{role.to_s.upcase}:
            Answer: #{data[:answer]}
            Reasoning: #{data[:reasoning]}
            Confidence: #{data[:confidence]}
          ARG
        end.join("\n" + "─" * 40 + "\n")
      end
      
      def parse_response(response)
        answer = response[/ANSWER:\s*(.+?)(?=REASONING:|$)/m, 1]&.strip
        reasoning = response[/REASONING:\s*(.+?)(?=CONFIDENCE:|$)/m, 1]&.strip
        confidence = response[/CONFIDENCE:\s*([0-9.]+)/m, 1]&.to_f || 0.5
        
        {
          answer: answer,
          reasoning: reasoning,
          confidence: confidence
        }
      end
      
      def consensus_reached?(round_result)
        answers = round_result.values.map { |r| r[:answer]&.downcase&.strip }
        return false if answers.any?(&:nil?)
        
        # Check for majority consensus
        answer_counts = answers.tally
        max_count = answer_counts.values.max
        
        consensus_ratio = max_count.to_f / answers.length
        consensus_ratio >= VOTING_THRESHOLD
      end
      
      def synthesize_final_answer(round_result)
        all_responses = round_result.map do |role, data|
          <<~RESPONSE
            #{role.to_s.upcase} (confidence: #{data[:confidence]}):
            Answer: #{data[:answer]}
            Reasoning: #{data[:reasoning]}
          RESPONSE
        end.join("\n\n")
        
        synthesis_prompt = <<~PROMPT
          You are the SYNTHESIZER in MASTER's Chamber system.
          
          Multiple expert models have deliberated on this question:
          #{@question}
          
          Their responses:
          #{all_responses}
          
          Provide a final synthesized answer that:
          1. Weighs each perspective by confidence level
          2. Identifies points of agreement
          3. Addresses points of disagreement
          4. Provides a clear, actionable conclusion
          
          Format:
          
          FINAL ANSWER:
          [Clear, definitive answer]
          
          SYNTHESIS:
          [How you reached this conclusion]
          
          CONFIDENCE: [0.0-1.0]
          
          DISSENTING VIEWS:
          [Any important minority opinions]
        PROMPT
        
        synthesis = call_llm(
          synthesis_prompt,
          model: CHAMBER_MODELS[:synthesizer],
          temperature: 0.3
        )
        
        {
          consensus_reached: @consensus_reached,
          rounds: @rounds.length,
          final_answer: synthesis,
          all_responses: round_result,
          metrics: @metrics
        }
      end
      
      def display_round_responses(responses)
        responses.each do |role, data|
          puts "\n  #{role_emoji(role)} #{role.to_s.upcase} (#{data[:model]})"
          puts "  Answer: #{data[:answer]}"
          puts "  Confidence: #{(data[:confidence] * 100).round}%"
        end
      end
      
      def role_emoji(role)
        {
          strategist: "🎯",
          analyst: "📊",
          critic: "🔍",
          synthesizer: "⚖️"
        }[role]
      end
    end
  end
end