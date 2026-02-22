# frozen_string_literal: true

# Plan — Live step-status tracker for the ReAct execution loop.
# Implements gist item #2: Codex CLI's update_plan with step statuses.
#
# Each step has one of: :pending, :in_progress, :completed, :skipped, :failed
# At most one step can be :in_progress at a time.
#
# Usage:
#   plan = Executor::Plan.new
#   plan.add("Read pipeline.rb to understand structure")
#   plan.add("Identify the pressure_pass extraction point")
#   plan.start(0)     # mark step 0 in_progress
#   plan.complete(0)  # mark step 0 completed, auto-advances
#   puts plan.to_dmesg

module MASTER
  class Executor
    class Plan
      Step = Struct.new(:description, :status, :started_at, :completed_at, keyword_init: true)

      STATUSES = %i[pending in_progress completed skipped failed].freeze
      STATUS_GLYPH = {
        pending:     " ",
        in_progress: ">",
        completed:   "+",
        skipped:     "-",
        failed:      "!",
      }.freeze

      def initialize
        @steps = []
      end

      def add(description)
        @steps << Step.new(description: description.to_s, status: :pending)
        self
      end

      # Mark step at index :in_progress. Completes any current :in_progress step first.
      def start(index)
        current = @steps.find { |s| s.status == :in_progress }
        current&.status = :completed
        current&.completed_at = Time.now

        step = @steps[index]
        return unless step

        step.status     = :in_progress
        step.started_at = Time.now
      end

      def complete(index)
        step = @steps[index]
        return unless step

        step.status       = :completed
        step.completed_at = Time.now
      end

      def fail(index, _reason = nil)
        step = @steps[index]
        return unless step

        step.status       = :failed
        step.completed_at = Time.now
      end

      def skip(index)
        step = @steps[index]
        step&.status = :skipped
      end

      # Auto-start the next :pending step after completing the current one
      def advance
        done = @steps.find_index { |s| s.status == :in_progress }
        complete(done) if done
        nxt = @steps.find_index { |s| s.status == :pending }
        start(nxt) if nxt
        nxt
      end

      def all_done?
        @steps.none? { |s| %i[pending in_progress].include?(s.status) }
      end

      def size = @steps.size
      def steps = @steps.dup

      # dmesg-compatible multi-line status string
      def to_dmesg
        return "plan: empty" if @steps.empty?

        @steps.each_with_index.map do |s, i|
          glyph = STATUS_GLYPH[s.status] || "?"
          "[#{glyph}] #{i + 1}. #{s.description}"
        end.join("\n")
      end

      # Single-line summary for inline progress display
      def summary
        done  = @steps.count { |s| s.status == :completed }
        total = @steps.size
        cur   = @steps.find { |s| s.status == :in_progress }
        cur_text = cur ? " → #{cur.description[0..50]}" : ""
        "plan: #{done}/#{total}#{cur_text}"
      end
    end
  end
end
