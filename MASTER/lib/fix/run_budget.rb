# frozen_string_literal: true

require "json"

module Master
  module Fix
    # What one /fix run has spent: model dollars and tokens (read from the
    # costs ledger the session writes), wall time per dmesg unit, and an ETA
    # from the passes already finished. It speaks at every pass boundary and
    # when a stage goes quiet, and it stops the run, loudly, past either limit.
    # ResourceBudget measures the host; this measures the run.
    class RunBudget
      DEFAULT_MAX_COST = 50.0
      DEFAULT_MAX_MINUTES = 480.0
      STALL_SECONDS = 120
      WARN_SHARE = 0.8
      UNIT = "budget0"
      COSTS = File.join(".master", "costs.jsonl")

      class << self
        attr_reader :current

        def begin_run(root:, max_passes:)
          finish_run
          @current = new(root:, max_passes:).start!
        end

        # A Result.err naming the exhausted limit, or nil while the run may go on.
        def pass_boundary(pass)
          reason = @current&.boundary(pass)
          reason && Master::Result.err(reason, category: :timeout)
        end

        def finish_run
          @current&.stop!
          @current = nil
        end

        def note_output(unit, text)
          @current&.note_output(unit, text)
        end
      end

      def initialize(root:, max_passes:, env: ENV, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     wall: -> { Time.now }, out: nil, say: nil, stall_seconds: STALL_SECONDS, poll_seconds: 5)
        @costs = File.join(root, COSTS)
        @max_passes = max_passes.to_i
        @max_cost = limit(env["MASTER_FIX_MAX_COST"], DEFAULT_MAX_COST)
        @max_minutes = limit(env["MASTER_FIX_MAX_MINUTES"], DEFAULT_MAX_MINUTES)
        @clock = clock
        @wall = wall
        @out = out || ->(line) { Master::Trace::Dmesg.status(UNIT, line) }
        @say = say || ->(text) { Master::Trace::Dmesg.emit(text) }
        @stall = stall_seconds
        @poll = poll_seconds
        @lock = Mutex.new
        @stages = Hash.new(0.0)
        @boundaries = {}
        @warned = false
      end

      def start!
        @started = @clock.call
        @started_wall = @wall.call.to_i
        @last_output = @started
        @last_unit = nil
        @last_text = nil
        @reported_at = nil
        @watchdog = Thread.new { watch } if @poll.positive?
        self
      end

      def stop!
        @watchdog&.kill
        @watchdog = nil
      end

      # Time between two lines belongs to the unit that spoke first.
      def note_output(unit, text)
        return if unit.to_s == UNIT || @started.nil?

        now = @clock.call
        @lock.synchronize do
          @stages[@last_unit] += now - @last_output if @last_unit
          @last_output = now
          @last_unit = unit.to_s
          @last_text = text.to_s[0, 60]
          @reported_at = nil
        end
      end

      def spend
        rows = File.file?(@costs) ? File.foreach(@costs).filter_map { |line| parse(line) } : []
        mine = rows.select { |row| row["ts"].to_i >= @started_wall }
        [mine.sum { |row| row["amount"].to_f }, mine.sum { |row| row["tokens"].to_i }]
      rescue SystemCallError
        [0.0, 0]
      end

      # Prints the budget line; returns the reason to stop, or nil.
      def boundary(pass)
        cost, tokens = spend
        minutes = (@clock.call - @started) / 60.0
        @boundaries[pass] = @clock.call
        @out.call(line(cost, tokens, minutes, pass))
        reason = exhausted(cost, minutes)
        warn_near(cost, minutes) unless reason
        @out.call(reason) if reason
        reason
      end

      # The watchdog calls this; a test drives it without a thread.
      def check_stall
        now = @clock.call
        message = @lock.synchronize do
          idle = now - @last_output
          next if idle < @stall || @reported_at

          @reported_at = now
          unit = @last_unit || "fix0"
          "#{unit}: still working on #{@last_text || "the current stage"}, #{idle.round}s without output"
        end
        @say.call(message) if message
        message
      end

      private

      def watch
        loop do
          sleep @poll
          check_stall
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::RunBudget.watch")
      end

      def limit(raw, default)
        return default if raw.to_s.strip.empty?
        return Float::INFINITY if %w[0 off none unlimited].include?(raw.to_s.strip.downcase)

        value = raw.to_f
        value.positive? ? value : default
      end

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def line(cost, tokens, minutes, pass)
        parts = ["spent $#{format("%.2f", cost)} / #{show(@max_cost, "$")}", "#{tokens} tokens",
                 "#{minutes.round(1)} / #{show(@max_minutes, "", "m")}"]
        parts << "stages #{stage_times}" unless stage_times.empty?
        parts << "pass #{pass}"
        parts << eta(pass)
        parts.join(", ")
      end

      def show(value, prefix = "", suffix = "")
        value.infinite? ? "no limit" : "#{prefix}#{value.round(2)}#{suffix}"
      end

      def stage_times
        top = @lock.synchronize { @stages.sort_by { |_, secs| -secs }.first(3) }
        top.map { |unit, secs| "#{unit} #{secs >= 90 ? "#{(secs / 60).round(1)}m" : "#{secs.round}s"}" }.join(" ")
      end

      def eta(pass)
        done = pass - 1
        return "ETA unknown" if done < 1 || @max_passes <= done

        first = @boundaries.min_by { |n, _| n }
        per_pass = (@boundaries.fetch(pass) - first.last) / [pass - first.first, 1].max
        "ETA ~#{(per_pass * (@max_passes - done) / 60.0).ceil}m"
      end

      def exhausted(cost, minutes)
        if cost > @max_cost
          "budget exhausted: spent $#{format("%.2f", cost)} over the $#{@max_cost.round(2)} limit " \
            "(MASTER_FIX_MAX_COST); stopping before the next pass"
        elsif minutes > @max_minutes
          "budget exhausted: #{minutes.round} minutes over the #{@max_minutes.round}-minute limit " \
            "(MASTER_FIX_MAX_MINUTES); stopping before the next pass"
        end
      end

      def warn_near(cost, minutes)
        return if @warned
        return unless cost > @max_cost * WARN_SHARE || minutes > @max_minutes * WARN_SHARE

        @warned = true
        @out.call("past #{(WARN_SHARE * 100).round}% of a run limit; raise MASTER_FIX_MAX_COST or MASTER_FIX_MAX_MINUTES to continue past it")
      end
    end
  end
end
