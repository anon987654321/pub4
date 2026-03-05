# frozen_string_literal: true

module MASTER
  class Session
    # PerStepReflection — evaluate each tool call's contribution toward the goal
    # Based on SAMULE: Multi-Level Reflection (EMNLP 2025, gistfile14 §2)
    # Adds per-step reflection layer; cross-task patterns logged to db_jsonl
    module PerStepReflection
      module_function

      # Reflect on a single ReAct step.
      # @param goal [String] original task goal
      # @param tool [String] tool that was called
      # @param observation [String] tool output
      # @param step [Integer] step number
      # @return [Hash] { useful: bool, progress: :advancing|:stalled|:diverging, note: String }
      def reflect(goal:, tool:, observation:, step:)
        obs = observation.to_s

        # Quick heuristics for progress assessment (avoids extra LLM call for most cases)
        result = if obs.start_with?("BLOCKED:", "Tool error:", "Error:") || obs.include?("not found")
                   { useful: false, progress: :stalled, note: "Step #{step}: #{tool} produced error/block" }
                 elsif obs.length < 10
                   { useful: false, progress: :stalled, note: "Step #{step}: #{tool} returned empty/minimal output" }
                 else
                   { useful: true, progress: :advancing, note: "Step #{step}: #{tool} returned #{obs.length} chars" }
                 end

        Logging.dmesg_log("refl0", message: "step=#{step} tool=#{tool} progress=#{result[:progress]}")
        result
      end

      # Cross-task reflection: after completing a task, extract patterns from step history.
      # Logs insights to db_jsonl for AutoTool-style learning.
      # @param goal [String]
      # @param history [Array<Hash>] step history from ReAct executor
      # @param success [Boolean]
      def cross_task_reflect(goal:, history:, success:)
        return unless defined?(Logging) && history.is_a?(Array) && !history.empty?

        tools_used = history.map { |h| h[:tool] || h[:action]&.split&.first }.compact.uniq
        stalled_steps = history.count { |h| h[:observation].to_s.start_with?("Error:", "BLOCKED:") }

        insight = {
          goal_prefix: goal.to_s[0..80],
          tools_sequence: tools_used,
          total_steps: history.size,
          stalled_steps: stalled_steps,
          success: success,
          efficiency: history.empty? ? 0 : ((history.size - stalled_steps).to_f / history.size).round(2),
        }

        Logging.dmesg_log("xtask0",
                          message: "goal=#{goal.to_s[0..80]} steps=#{history.size} stalled=#{stalled_steps} success=#{success}")
        insight
      end
    end
  end
end
