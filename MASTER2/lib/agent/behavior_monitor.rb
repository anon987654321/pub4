# frozen_string_literal: true

module MASTER
  class AgentFirewall
    # BehaviorMonitor — track session baselines and flag anomalies
    # Fills the "behavioral monitoring" gap identified in gistfile14 §4
    # (847 Test Cases paper: combined defenses cut attacks 73% → 8.7%)
    module BehaviorMonitor
      module_function

      # Baseline window: track last N actions for anomaly detection
      BASELINE_WINDOW = 50

      @session_baseline = Hash.new { |h, k| h[k] = [] }
      @baseline_mutex = Mutex.new

      # Record an action for baseline tracking.
      # @param action [String] tool name or action type
      # @param session_id [String]
      def record(action, session_id:)
        @baseline_mutex.synchronize do
          history = @session_baseline[session_id]
          history << { action: action, at: Time.now.to_i }
          # Keep only the last BASELINE_WINDOW entries
          @session_baseline[session_id] = history.last(BASELINE_WINDOW)
        end
      end

      # Check if current action is anomalous relative to session baseline.
      # @param action [String]
      # @param session_id [String]
      # @return [Hash] { anomalous: bool, reason: String|nil, score: Float }
      def check(action, session_id:)
        @baseline_mutex.synchronize do
          history = @session_baseline[session_id]
          return { anomalous: false, reason: nil, score: 0.0 } if history.size < 10

          # Count frequency of this action in baseline
          freq = history.count { |e| e[:action] == action }.to_f / history.size
          # Actions never seen before in this session get higher anomaly score
          score = freq < 0.05 ? 0.8 : 0.0

          # Rate spike: more than 5 identical actions in last 10
          recent = history.last(10).count { |e| e[:action] == action }
          score = [score, recent > 5 ? 0.9 : 0.0].max

          anomalous = score >= 0.8
          reason = anomalous ? "Action '#{action}' anomalous (score=#{score.round(2)}, freq=#{freq.round(2)})" : nil

          if anomalous
            Logging.dmesg_log("behav0",
                              message: "action=#{action} score=#{score.round(2)} anomalous=#{anomalous}")
          end

          { anomalous: anomalous, reason: reason, score: score }
        end
      end

      # Reset baseline for a session (on session end).
      def reset(session_id:)
        @baseline_mutex.synchronize { @session_baseline.delete(session_id) }
      end
    end
  end
end
