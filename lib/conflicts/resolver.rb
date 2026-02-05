# frozen_string_literal: true

module Master
  module Conflicts
    class Resolver
      attr_reader :resolutions
      
      def initialize(llm: nil, memory: nil)
        @llm = llm || Master::LLM.new
        @memory = memory
        @resolutions = []
      end
      
      # Detect conflicts between principles in violations
      def detect_conflicts(violations)
        conflicts = []
        
        # Group violations by location
        by_location = violations.group_by do |v|
          "#{v[:file]}:#{v[:line]}"
        end
        
        # Find locations with multiple principle violations
        by_location.each do |location, viols|
          next unless viols.size > 1
          
          principles = viols.map { |v| v[:principle] }
          
          # Check for known conflict pairs
          if conflicting_principles?(principles)
            conflicts << {
              location: location,
              principles: principles,
              violations: viols,
              type: determine_conflict_type(principles)
            }
          end
        end
        
        conflicts
      end
      
      # Resolve a conflict using LLM arbitration
      def resolve(conflict, interactive: true)
        prompt = build_resolution_prompt(conflict)
        
        result = @llm.ask(prompt, tier: :strong)
        
        return Result.err("Resolution failed: #{result.error}") unless result.ok?
        
        recommendation = parse_resolution(result.value)
        
        if interactive
          # Ask user to confirm
          puts "\nConflict detected:"
          puts "  Location: #{conflict[:location]}"
          puts "  Principles: #{conflict[:principles].join(', ')}"
          puts "\nRecommendation: #{recommendation[:decision]}"
          puts "Reason: #{recommendation[:reason]}"
          puts "\nAccept? [y/n/explain] "
          
          response = gets&.strip&.downcase
          
          case response
          when "y", "yes"
            accepted = true
          when "explain"
            puts "\nDetailed explanation:"
            puts recommendation[:explanation] || "No additional details available"
            puts "\nAccept? [y/n] "
            accepted = gets&.strip&.downcase&.start_with?("y")
          else
            accepted = false
          end
        else
          accepted = true
        end
        
        resolution = {
          conflict: conflict,
          recommendation: recommendation,
          accepted: accepted,
          timestamp: Time.now.utc.iso8601
        }
        
        @resolutions << resolution
        
        # Record in memory if available
        @memory&.record_decision(
          conflict[:location],
          conflict,
          { type: "conflict_resolved", action: accepted ? "accepted" : "rejected" }
        )
        
        Result.ok(resolution)
      end
      
      # Resolve multiple conflicts
      def resolve_all(conflicts, interactive: true)
        results = conflicts.map do |conflict|
          resolve(conflict, interactive: interactive)
        end
        
        Result.ok(
          total: conflicts.size,
          resolved: results.count(&:ok?),
          accepted: @resolutions.count { |r| r[:accepted] }
        )
      end
      
      private
      
      # Known conflicting principle pairs
      CONFLICT_PAIRS = {
        ["PRINCIPLE_DRY", "PRINCIPLE_WET"] => :dry_vs_wet,
        ["PRINCIPLE_YAGNI", "PRINCIPLE_EXTENSIBILITY"] => :simplicity_vs_flexibility,
        ["SOLID_SRP", "PRINCIPLE_COHESION"] => :separation_vs_cohesion,
        ["PRINCIPLE_PERFORMANCE", "PRINCIPLE_READABILITY"] => :speed_vs_clarity
      }.freeze
      
      def conflicting_principles?(principles)
        # Check if any pair of principles is a known conflict
        principles.combination(2).any? do |pair|
          CONFLICT_PAIRS.key?(pair.sort) || CONFLICT_PAIRS.key?(pair.reverse.sort)
        end
      end
      
      def determine_conflict_type(principles)
        pair = principles.sort
        CONFLICT_PAIRS[pair] || CONFLICT_PAIRS[pair.reverse] || :unknown
      end
      
      def build_resolution_prompt(conflict)
        principles_desc = conflict[:principles].map do |p|
          violation = conflict[:violations].find { |v| v[:principle] == p }
          "#{p}: #{violation[:description]}"
        end.join("\n")
        
        <<~PROMPT
          Principle conflict detected. Please arbitrate:
          
          Location: #{conflict[:location]}
          
          Conflicting Principles:
          #{principles_desc}
          
          Conflict Type: #{conflict[:type]}
          
          Please analyze and provide:
          1. Which principle should take priority
          2. Clear reasoning for your decision
          3. Recommended action
          
          Consider:
          - Context and domain concerns
          - Long-term maintainability
          - Team practices
          - Severity of violations
          
          Format your response as:
          DECISION: [Principle name]
          REASON: [Brief explanation]
          ACTION: [What to do]
        PROMPT
      end
      
      def parse_resolution(response)
        decision = response[/DECISION:\s*(.+?)(?:\n|$)/i, 1]&.strip
        reason = response[/REASON:\s*(.+?)(?:\n|ACTION:|\z)/mi, 1]&.strip
        action = response[/ACTION:\s*(.+?)$/mi, 1]&.strip
        
        {
          decision: decision || "Unknown",
          reason: reason || "No reason provided",
          action: action || "No action specified",
          explanation: response
        }
      end
    end
  end
end
