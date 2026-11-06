# frozen_string_literal: true

require_relative "../io/lane_silence"
require_relative "resource_budget"
require_relative "run_budget"

module Master
  module Fix
    # Paces a model repair before its call. Two things burned files on 2026-11-05:
    #
    # A run pinned to one lane (claude-cli, no failover) met LaneSilence's five-minute cool-off,
    # and every file in it failed at once, "offline: no lane answers". A lane whose cool-off holds
    # every candidate is now waited out, polling, so the next file meets an answering lane.
    #
    # The malformed replies began with this 8-core Mac at load 12.9. A host whose one-minute load
    # is over ResourceBudget's warn line (1.5 per CPU) gets up to LOAD_WAIT_MAX_S to come down.
    #
    # Both waits happen only inside a /fix run and end at its deadline or its stop. Each poll says so
    # on the bus (fix_loop:model_wait), so RunPulse does not read a paced run as stalled.
    module ModelGate
      POLL_S = 15
      LOAD_WAIT_MAX_S = 300
      # The last stretch of a run is for its proof, not for waiting on a lane.
      RESERVE_S = 120

      module_function

      def before_call(agent, resources:, bus: nil, sleeper: ->(seconds) { sleep(seconds) })
        gate = { bus:, sleeper:, waited: 0 }
        wait_out_cool_off(lane_models(agent), gate)
        wait_for_load(resources, gate)
        nil
      end

      def wait_out_cool_off(models, gate)
        return if models.empty?

        limit = Master::Io::LaneSilence::SILENCE_COOLOFF_S + POLL_S
        while models.all? { |model| cooling_off?(model) } && gate[:waited] < limit && time_left?
          pause(gate, "#{models.first} is in its cool-off; waiting #{POLL_S}s instead of failing the file")
        end
      end

      def wait_for_load(resources, gate)
        started = gate[:waited]
        loop do
          load, ceiling = resources.load_pressure
          break unless load && load > ceiling
          break if gate[:waited] - started >= LOAD_WAIT_MAX_S || !time_left?

          pause(gate, format("load %<load>.1f is over %<ceiling>.1f; waiting %<poll>ds before the model call",
                             load:, ceiling:, poll: POLL_S))
        end
      end

      def pause(gate, line)
        gate[:bus]&.publish("fix_loop:model_wait", reason: line)
        Master::Trace::Dmesg.status("fix0", line) if (gate[:waited] % 60).zero?
        gate[:sleeper].call(POLL_S)
        gate[:waited] += POLL_S
      end

      # A lane LaneSilence paused, not one whose quota is spent for hours: only a cool-off ends soon.
      def cooling_off?(model) = Master::Io::LaneState.silent?(model)

      def time_left?
        return false if RunBudget.stopping

        left = RunBudget.seconds_left
        !left.nil? && left > RESERVE_S + POLL_S
      end

      # A stub agent may have no model; a real one names the lane it calls.
      def lane_models(agent)
        return [] unless agent.class.method_defined?(:model)

        [agent.model].compact.map(&:to_s).reject(&:empty?)
      end
    end
  end
end
