# frozen_string_literal: true

require "timeout"

module Master
  module Fix
    # One tiny request per live lane before the model phase, under a latency
    # budget. A lane that errors or answers too slowly is dropped for the run
    # (LaneQuota.drop_for_run!), so the first file does not discover it and the
    # next 1,650 do not rediscover it. The 2026-10-12 run stood 46 minutes at
    # 0 of 1651 files on free-class lanes that were alive and answering far too
    # slowly to repair anything.
    module LaneProbe
      PROMPT = "Reply with the single word OK."
      BUDGET_S = 20
      MAX_LANES = 6

      Row = Struct.new(:lane, :model, :status, :seconds, :detail, keyword_init: true)

      module_function

      def budget_s
        Integer(ENV.fetch("MASTER_FIX_PROBE_S", BUDGET_S.to_s), exception: false) || BUDGET_S
      end

      def enabled? = ENV["MASTER_FIX_PROBE"] != "0"

      # Probes the first model of each distinct live lane, in selection order,
      # and drops the lanes that are slow or dead. `ask` is
      # ->(model) { reply }, so a test drives it with a fake lane.
      def run(models:, ask:, budget: budget_s, max_lanes: MAX_LANES, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        rows = pick(models, max_lanes).map { |model| probe(model, ask:, budget:, clock:) }
        rows.reject { |row| row.status == :ok }.each do |row|
          Master::Io::LaneQuota.drop_for_run!(row.lane, "probe #{row.status}: #{row.detail}")
        end
        rows.each { |row| say(row) }
        say_verdict(rows)
        rows
      end

      def pick(models, max_lanes)
        lanes = Master::Io::LaneState
        Master::Io::LaneSelection.order(Array(models)).uniq { |model| lanes.lane_of(model) }.first(max_lanes)
      end

      def probe(model, ask:, budget:, clock:)
        lane = Master::Io::LaneState.lane_of(model)
        started = clock.call
        Fiber[:master_operation] = :lane_probe
        reply = Timeout.timeout(budget) { ask.call(model) }
        seconds = clock.call - started
        return Row.new(lane:, model:, status: :empty, seconds:, detail: "empty reply") if reply.to_s.strip.empty?
        return Row.new(lane:, model:, status: :slow, seconds:, detail: "answered in #{seconds.round(1)}s, budget #{budget}s") if seconds > budget

        Row.new(lane:, model:, status: :ok, seconds:, detail: "answered")
      rescue Timeout::Error
        Row.new(lane:, model:, status: :slow, seconds: clock.call - started, detail: "no answer within #{budget}s")
      rescue StandardError => e
        Row.new(lane:, model:, status: :dead, seconds: clock.call - started, detail: "#{e.class}: #{e.message}"[0, 120])
      ensure
        Fiber[:master_operation] = nil
      end

      def say(row)
        Master::Trace::Dmesg.status("fix0", "lane probe #{row.lane} (#{row.model}) #{row.status} #{row.seconds.round(1)}s, #{row.detail}")
      end

      def say_verdict(rows)
        live = rows.count { |row| row.status == :ok }
        text = live.zero? ? "lane probe: no lane answered within budget; the model phase has nothing to run on" : "lane probe: #{live} of #{rows.size} lane(s) usable"
        Master::Trace::Dmesg.status("fix0", text)
      end

      # The probe a run uses: a bare ask on the named lane, no failover, no law preamble.
      def ask_with(agent)
        ->(model) { agent.ask_once(PROMPT, model:, failover: false, law: false) }
      end
    end
  end
end
