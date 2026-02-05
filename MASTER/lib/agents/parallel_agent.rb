# frozen_string_literal: true

require 'concurrent'

module MASTER
  module Agents
    class ParallelAgent < BaseAgent
      attr_reader :agents
      
      def initialize(agents: [], context: {}, strategy: :all)
        super(context)
        @agents = agents # Array of {agent: AgentClass, config: {}}
        @strategy = strategy # :all, :first, :fastest, :best
        @results = []
      end
      
      def execute
        puts "⚡ Parallel Execution: #{@agents.length} agents"
        puts "   Strategy: #{@strategy}"
        puts "━" * 60
        
        case @strategy
        when :all
          execute_all
        when :first
          execute_first
        when :fastest
          execute_fastest
        when :best
          execute_best
        else
          raise ArgumentError, "Unknown strategy: #{@strategy}"
        end
      end
      
      private
      
      # Execute all agents and return all results
      def execute_all
        futures = @agents.map do |agent_config|
          Concurrent::Future.execute do
            agent_class = agent_config[:agent]
            config = agent_config[:config] || {}
            
            puts "   ▸ Starting #{agent_class.name}..."
            
            agent = agent_class.new(context: @context.merge(config))
            result = agent.execute_with_retry
            
            puts "   ✓ #{agent_class.name} completed"
            
            {
              agent: agent_class.name,
              result: result,
              metrics: agent.metrics
            }
          end
        end
        
        # Wait for all to complete
        results = futures.map(&:value!)
        
        # Aggregate metrics
        results.each do |r|
          @metrics[:total_cost] += r[:metrics][:total_cost]
          @metrics[:total_tokens] += r[:metrics][:total_tokens]
        end
        
        @metrics[:execution_time] = futures.map { |f| f.value![:metrics][:execution_time] }.max
        
        {
          strategy: :all,
          results: results,
          metrics: @metrics
        }
      end
      
      # Return first successful result
      def execute_first
        latch = Concurrent::CountDownLatch.new(1)
        result_box = Concurrent::AtomicReference.new(nil)
        
        @agents.each do |agent_config|
          Thread.new do
            next if result_box.get # Someone already finished
            
            agent_class = agent_config[:agent]
            config = agent_config[:config] || {}
            
            begin
              agent = agent_class.new(context: @context.merge(config))
              result = agent.execute_with_retry
              
              if result_box.compare_and_set(nil, {
                agent: agent_class.name,
                result: result,
                metrics: agent.metrics
              })
                puts "   ✓ #{agent_class.name} finished first!"
                latch.count_down
              end
            rescue => e
              puts "   ✗ #{agent_class.name} failed: #{e.message}"
            end
          end
        end
        
        # Wait for first completion
        latch.wait(300) # 5 minute timeout
        
        final_result = result_box.get
        raise "All agents failed" unless final_result
        
        @metrics.merge!(final_result[:metrics])
        final_result
      end
      
      # Execute all, return fastest
      def execute_fastest
        start_times = {}
        
        futures = @agents.map do |agent_config|
          Concurrent::Future.execute do
            agent_class = agent_config[:agent]
            config = agent_config[:config] || {}
            
            start_time = Time.now
            start_times[agent_class.name] = start_time
            
            agent = agent_class.new(context: @context.merge(config))
            result = agent.execute_with_retry
            
            duration = Time.now - start_time
            
            {
              agent: agent_class.name,
              result: result,
              metrics: agent.metrics,
              duration: duration
            }
          end
        end
        
        results = futures.map(&:value!)
        fastest = results.min_by { |r| r[:duration] }
        
        puts "   🏆 Fastest: #{fastest[:agent]} (#{fastest[:duration].round(2)}s)"
        
        fastest
      end
      
      # Execute all, return best by custom scoring
      def execute_best
        results = execute_all[:results]
        
        # Score each result (can be customized)
        scored_results = results.map do |r|
          score = score_result(r)
          r.merge(score: score)
        end
        
        best = scored_results.max_by { |r| r[:score] }
        
        puts "   🏆 Best: #{best[:agent]} (score: #{best[:score].round(2)})"
        
        best
      end
      
      # Default scoring function (can be overridden)
      def score_result(result)
        # Simple scoring: lower cost = higher score
        1.0 / (result[:metrics][:total_cost] + 0.001)
      end
    end
  end
end