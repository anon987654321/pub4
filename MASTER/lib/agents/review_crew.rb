# frozen_string_literal: true
begin
  require "async"
rescue LoadError
  # async gem not available - will use sequential execution
end

require_relative 'base_agent'
require_relative 'security_agent'
require_relative 'performance_agent'
require_relative 'style_agent'
require_relative 'architecture_agent'

module MASTER
  module Agents
    class ReviewCrew
      attr_reader :agents, :results

      def initialize(llm:, principles: [])
        @llm = llm
        @principles = principles
        @agents = [
          SecurityAgent.new(llm: llm, principles: principles),
          PerformanceAgent.new(llm: llm, principles: principles),
          StyleAgent.new(llm: llm, principles: principles),
          ArchitectureAgent.new(llm: llm, principles: principles)
        ]
        @results = {}
      end

      # Run all agents in parallel
      def review(code, file_path = nil, &progress_block)
        @results = {}
        
        puts "🚀 Starting multi-agent code review..."
        puts "   Agents: #{@agents.map(&:name).join(', ')}"
        puts

        # Run agents in parallel using Async if available, otherwise sequential
        if defined?(Async)
          run_parallel_with_async(code, file_path, &progress_block)
        else
          run_sequential(code, file_path, &progress_block)
        end

        # Synthesize findings with LLM
        synthesis = synthesize_findings

        {
          agents: @results,
          synthesis: synthesis,
          summary: generate_summary
        }
      end

      private

      def run_parallel_with_async(code, file_path, &progress_block)
        Async do |task|
          @agents.each do |agent|
            task.async do
              progress_block&.call(agent.name, :started)
              
              start_time = Time.now
              findings = agent.analyze(code, file_path)
              duration = Time.now - start_time
              
              @results[agent.name] = {
                findings: findings,
                duration: duration,
                severity_counts: count_by_severity(findings)
              }
              
              progress_block&.call(agent.name, :completed, findings.size)
            end
          end
        end
      end

      def run_sequential(code, file_path, &progress_block)
        @agents.each do |agent|
          progress_block&.call(agent.name, :started)
          
          start_time = Time.now
          findings = agent.analyze(code, file_path)
          duration = Time.now - start_time
          
          @results[agent.name] = {
            findings: findings,
            duration: duration,
            severity_counts: count_by_severity(findings)
          }
          
          progress_block&.call(agent.name, :completed, findings.size)
        end
      end

      def count_by_severity(findings)
        counts = Hash.new(0)
        findings.each { |f| counts[f[:severity]] += 1 }
        counts
      end

      def synthesize_findings
        all_findings = @results.values.flat_map { |r| r[:findings] }
        return nil if all_findings.empty?

        # Group by severity
        critical = all_findings.select { |f| f[:severity] == :critical }
        high = all_findings.select { |f| f[:severity] == :high }
        medium = all_findings.select { |f| f[:severity] == :medium }

        prompt = <<~PROMPT
          You are a senior code reviewer synthesizing findings from multiple specialized agents.

          CRITICAL ISSUES (#{critical.size}):
          #{format_findings(critical.first(5))}

          HIGH SEVERITY (#{high.size}):
          #{format_findings(high.first(5))}

          MEDIUM SEVERITY (#{medium.size}):
          #{format_findings(medium.first(5))}

          Provide a concise meta-review (max 300 words):
          1. Top 3 priority fixes
          2. Overall code quality assessment (1-10)
          3. Recommended next steps
          4. Estimated effort (hours)

          Be direct and actionable.
        PROMPT

        result = @llm.chat(prompt, tier: :strong)
        result.ok? ? result.value : "Synthesis failed: #{result.error}"
      end

      def format_findings(findings)
        return "None" if findings.empty?
        
        findings.map do |f|
          location = f[:line] ? "Line #{f[:line]}" : "General"
          "- [#{f[:agent]}] #{location}: #{f[:message]}"
        end.join("\n")
      end

      def generate_summary
        all_findings = @results.values.flat_map { |r| r[:findings] }
        
        severity_totals = Hash.new(0)
        all_findings.each { |f| severity_totals[f[:severity]] += 1 }

        {
          total_findings: all_findings.size,
          by_severity: severity_totals,
          by_agent: @results.transform_values { |r| r[:findings].size },
          total_duration: @results.values.sum { |r| r[:duration] }
        }
      end
    end
  end
end
