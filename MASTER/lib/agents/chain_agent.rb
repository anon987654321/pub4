# frozen_string_literal: true

module MASTER
  module Agents
    class ChainAgent < BaseAgent
      attr_reader :stages
      
      def initialize(stages: [], context: {})
        super(context)
        @stages = stages # Array of agent classes or instances
        @stage_results = []
      end
      
      def execute
        puts "⛓️  Agent Chain: #{@stages.length} stages"
        puts "━" * 60
        
        current_input = @context
        
        @stages.each_with_index do |stage_config, index|
          stage_name = stage_config[:name] || "Stage #{index + 1}"
          agent_class = stage_config[:agent]
          transform = stage_config[:transform] # Optional input transformation
          
          puts "\n#{index + 1}. #{stage_name}"
          puts "   Agent: #{agent_class.name}"
          
          # Transform input if needed
          stage_input = transform ? transform.call(current_input) : current_input
          
          # Execute stage
          agent = agent_class.new(context: stage_input)
          stage_result = agent.execute_with_retry(
            max_retries: stage_config[:retries] || 3,
            fallback_models: stage_config[:fallback_models]
          )
          
          # Store result
          @stage_results << {
            stage: stage_name,
            agent: agent_class.name,
            input: stage_input,
            output: stage_result,
            metrics: agent.metrics
          }
          
          # Update metrics
          @metrics[:total_cost] += agent.metrics[:total_cost]
          @metrics[:total_tokens] += agent.metrics[:total_tokens]
          @metrics[:execution_time] += agent.metrics[:execution_time]
          
          # Output becomes input for next stage
          current_input = stage_result
          
          puts "   ✓ Completed (cost: $#{agent.metrics[:total_cost].round(4)})"
        end
        
        {
          final_result: current_input,
          stage_results: @stage_results,
          metrics: @metrics
        }
      end
      
      # Helper to build chains fluently
      class Builder
        def initialize
          @stages = []
        end
        
        def then(agent_class, name: nil, retries: 3, fallback_models: nil, transform: nil)
          @stages << {
            agent: agent_class,
            name: name,
            retries: retries,
            fallback_models: fallback_models,
            transform: transform
          }
          self
        end
        
        def build(context: {})
          ChainAgent.new(stages: @stages, context: context)
        end
      end
      
      def self.build(&block)
        builder = Builder.new
        builder.instance_eval(&block)
        builder
      end
    end
  end
end