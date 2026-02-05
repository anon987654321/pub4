# frozen_string_literal: true

module MASTER
  module Agents
    class BaseAgent
      attr_reader :context, :history, :metrics
      
      class AgentError < StandardError; end
      class RetryExhausted < AgentError; end
      class BudgetExceeded < AgentError; end
      
      def initialize(context = {})
        @context = context
        @history = []
        @metrics = {
          total_cost: 0.0,
          total_tokens: 0,
          execution_time: 0.0,
          retries: 0,
          model_switches: 0
        }
      end
      
      # Main execution method - must be implemented by subclasses
      def execute
        raise NotImplementedError, "Subclasses must implement #execute"
      end
      
      # Execute with retry logic and fallback models
      def execute_with_retry(max_retries: 3, fallback_models: nil)
        attempt = 0
        last_error = nil
        
        loop do
          begin
            start_time = Time.now
            result = execute
            @metrics[:execution_time] += Time.now - start_time
            
            log_execution(result, success: true)
            return result
            
          rescue => e
            attempt += 1
            @metrics[:retries] = attempt
            last_error = e
            
            log_execution(nil, success: false, error: e)
            
            if attempt >= max_retries
              # Try fallback models if available
              if fallback_models && !fallback_models.empty?
                return try_fallback_models(fallback_models)
              else
                raise RetryExhausted, "Failed after #{max_retries} attempts: #{e.message}"
              end
            end
            
            sleep_duration = exponential_backoff(attempt)
            puts "  ⚠️  Retry #{attempt}/#{max_retries} after #{sleep_duration}s..."
            sleep(sleep_duration)
          end
        end
      end
      
      protected
      
      # Call LLM with automatic cost tracking
      def call_llm(prompt, model: default_model, temperature: 0.7, max_tokens: 4000)
        llm = MASTER::LLM.new(
          prompt,
          model: model,
          temperature: temperature,
          max_tokens: max_tokens
        )
        
        response = llm.ask(prompt)
        
        # Track metrics
        @metrics[:total_cost] += llm.total_cost
        @metrics[:total_tokens] += llm.last_tokens
        
        # Add to history
        @history << {
          timestamp: Time.now,
          model: model,
          prompt: prompt,
          response: response,
          cost: llm.total_cost,
          tokens: llm.last_tokens
        }
        
        response
      end
      
      # Default model for this agent
      def default_model
        "claude-3.5-sonnet"
      end
      
      # Exponential backoff for retries
      def exponential_backoff(attempt)
        [2 ** attempt, 32].min
      end
      
      # Try fallback models in order
      def try_fallback_models(models)
        models.each_with_index do |model, index|
          begin
            puts "  🔄 Trying fallback model: #{model}"
            @metrics[:model_switches] += 1
            
            # Temporarily override default model
            original_model = default_model
            define_singleton_method(:default_model) { model }
            
            result = execute
            
            # Restore original model
            define_singleton_method(:default_model) { original_model }
            
            return result
            
          rescue => e
            if index == models.length - 1
              raise RetryExhausted, "All fallback models failed: #{e.message}"
            end
          end
        end
      end
      
      # Log execution to database/file
      def log_execution(result, success:, error: nil)
        log_entry = {
          agent: self.class.name,
          timestamp: Time.now,
          success: success,
          context: @context,
          metrics: @metrics,
          result: result,
          error: error&.message
        }
        
        # Save to database if available
        if defined?(AgentExecution)
          AgentExecution.create!(log_entry)
        end
        
        # Also log to file
        File.open("#{MASTER::ROOT}/log/agent_executions.log", "a") do |f|
          f.puts(JSON.pretty_generate(log_entry))
        end
      end
    end
  end
end