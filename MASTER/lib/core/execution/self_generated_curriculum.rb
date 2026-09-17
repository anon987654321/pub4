# frozen_string_literal: true

module Master::Core::Execution
  # SelfGeneratedCurriculum — an adaptive learning system.
  #
  # It analyzes the Episode Ledger to identify failure-prone task classes
  # and generates targeted exercises to improve the agent's performance
  # in those specific areas.
  class SelfGeneratedCurriculum
    attr_reader :failure_stats

    def initialize
      @failure_stats = Hash.new { |h, k| h[k] = { fails: 0, total: 0 } }
    end

    # Analyze a completed episode to update failure frequency.
    def analyze_episode(episode)
      task_class = episode.intent # Simplified for now
      @failure_stats[task_class][:total] += 1
      @failure_stats[task_class][:fails] += 1 if episode.outcome == :failed
    end

    # Generate a targeted exercise for the most failure-prone task.
    def generate_exercise
      worst_task = @failure_stats.max_by { |_, stats|
        stats[:fails].to_f / [stats[:total], 1].max
      }&.first

      return nil unless worst_task

      {
        task: worst_task,
        type: :recovery_drill,
        goal: "Targeted exercise for #{worst_task}: solve a known failure case."
      }
    end
  end
end
