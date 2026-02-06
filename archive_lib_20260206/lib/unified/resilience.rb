# frozen_string_literal: true

# Never give up engine - Systematic problem solving
module MASTER
  module Unified
    class Resilience
      attr_reader :attempts, :learnings, :state

      def initialize
        @attempts = []
        @learnings = []
        @state = :active
        @max_iterations = 100
        @reset_threshold = 10
      end

      # Act-React loop
      def solve(problem, &block)
        iteration = 0
        
        while iteration < @max_iterations && @state == :active
          hypothesis = generate_hypothesis(problem, iteration)
          action = design_test(hypothesis)
          
          begin
            result = block.call(action)
            learning = observe(result, action)
            
            @attempts << { 
              iteration: iteration, 
              hypothesis: hypothesis, 
              result: result,
              success: learning[:success]
            }
            
            @learnings << learning
            
            return Result.ok(result) if learning[:success]
            
            # Check if we should reset
            if should_reset?
              reset_and_simplify(problem)
            end
            
          rescue StandardError => e
            @attempts << {
              iteration: iteration,
              hypothesis: hypothesis,
              error: e.message,
              success: false
            }
          end
          
          iteration += 1
        end
        
        Result.err("Max iterations reached without solution")
      end

      # Problem-solving loop helpers
      def generate_hypothesis(problem, iteration)
        if iteration == 0
          "Try the most straightforward approach"
        elsif iteration < 5
          "Adjust parameters from previous attempt"
        elsif iteration < 10
          "Try a different approach entirely"
        else
          "Simplify the problem and solve a subset"
        end
      end

      def design_test(hypothesis)
        {
          hypothesis: hypothesis,
          test_plan: "Execute hypothesis and observe results",
          expected_outcome: "Solution or learning"
        }
      end

      def observe(result, action)
        {
          result: result,
          action: action,
          success: result != nil && result != false,
          timestamp: Time.now
        }
      end

      def should_reset?
        return false if @attempts.length < @reset_threshold
        
        recent_attempts = @attempts.last(@reset_threshold)
        all_failed = recent_attempts.all? { |a| !a[:success] }
        
        all_failed
      end

      def reset_and_simplify(problem)
        puts "  ⟲ Resetting approach (#{@attempts.length} attempts)"
        @state = :resetting
        
        # Clear recent failed attempts from consideration
        @attempts = @attempts.first(5)
        
        @state = :active
      end

      # Creative problem solving strategies
      def apply_analogy(problem, domain)
        analogies = {
          detective: "Investigate clues, eliminate suspects",
          architect: "Design structure, ensure stability",
          gardener: "Plant seeds, nurture growth, prune excess",
          mechanic: "Diagnose symptoms, isolate problem, replace part"
        }
        
        analogies[domain.to_sym] || "Apply #{domain} thinking to #{problem}"
      end

      def apply_constraints(problem, constraint)
        constraints = {
          time: "If you had 5 minutes, what would you do?",
          tools: "If you couldn't use a debugger, how would you proceed?",
          explanation: "If you had to explain this to a 5-year-old, how would you?"
        }
        
        constraints[constraint.to_sym] || constraint
      end

      def apply_extreme_cases(problem)
        [
          "What if input was empty?",
          "What if input was huge (1 billion items)?",
          "What if input was malicious?",
          "What if input was negative?",
          "What if input was null?"
        ]
      end

      # Status reporting
      def status
        {
          attempts: @attempts.length,
          successes: @attempts.count { |a| a[:success] },
          failures: @attempts.count { |a| !a[:success] },
          state: @state,
          learnings: @learnings.length
        }
      end

      def report
        status_data = status
        
        [
          "Resilience Engine Status:",
          "  Attempts: #{status_data[:attempts]}",
          "  Successes: #{status_data[:successes]}",
          "  Failures: #{status_data[:failures]}",
          "  State: #{status_data[:state]}",
          "  Learnings: #{status_data[:learnings]}"
        ].join("\n")
      end

      # Reset protocol
      def reset!
        @attempts = []
        @learnings = []
        @state = :active
      end

      def give_up
        @state = :abandoned
        Result.err("Problem abandoned after #{@attempts.length} attempts")
      end

      # Five Whys technique
      def five_whys(problem)
        whys = ["Why does #{problem} happen?"]
        
        4.times do |i|
          whys << "Why does that happen? (level #{i + 2})"
        end
        
        {
          technique: "Five Whys",
          questions: whys,
          instruction: "Answer each why to drill down to root cause"
        }
      end

      # Rubber duck debugging
      def rubber_duck(code)
        {
          technique: "Rubber Duck Debugging",
          instructions: [
            "1. Explain the code line by line",
            "2. Say what you expect each line to do",
            "3. Say what it actually does",
            "4. Notice the discrepancy"
          ],
          code: code
        }
      end

      # Binary search debugging
      def binary_search_debug(problem_space)
        {
          technique: "Binary Search Debugging",
          instructions: [
            "1. Identify the working and broken states",
            "2. Find the midpoint between them",
            "3. Test the midpoint",
            "4. Eliminate half the problem space",
            "5. Repeat until you find the exact breaking point"
          ],
          problem_space: problem_space
        }
      end

      # Minimal reproduction
      def minimal_reproduction(context)
        {
          technique: "Minimal Reproduction",
          instructions: [
            "1. Start with the full failing case",
            "2. Remove one piece at a time",
            "3. If it still fails, keep the removal",
            "4. If it stops failing, restore that piece",
            "5. Continue until you have the smallest failing example"
          ],
          context: context
        }
      end
    end
  end
end
