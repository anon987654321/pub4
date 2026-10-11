# frozen_string_literal: true

module Master
  module Review
    class LLMDispatcher
      # Every lane failing is one condition, not two hundred failures. On
      # 2026-09-16 a /fix ran 194 model calls and 178 of them failed: the free
      # OpenRouter tier was out for the day, Gemini was out of quota, the claude
      # binary hung and was killed, and a 3B local model timed out at 250s. Each
      # semantic rule still walked all four lanes, so an hour of wall clock
      # bought nothing but a longer log.
      #
      # After SILENT_AFTER consecutive failures of one lane with no answer from it
      # in between, that lane refuses for SILENCE_COOLOFF_S and says so once, with
      # the lane's last words. One success from the lane clears it, so a provider
      # coming back needs no restart. The refusal is :no_api_key, which callers
      # already treat as permanent and skip rather than retry.
      #
      # Per lane, because on 2026-10-11 a /fix council spent agy's weekly quota on
      # 26 persona calls, the twelve failures tripped one shared door, and the claude
      # lane (which answers in four seconds) was refused before it was ever asked:
      # "no lane answered" with $0.00 spent. A spent lane is not a silent door.
      #
      # Process-wide, and its own module because the state is: the dispatcher is
      # built per session and the lanes are shared by all of them.
      module LaneSilence
        SILENT_AFTER = 12
        SILENCE_COOLOFF_S = 300
        ANY = "any"

        @mutex = Mutex.new
        @lanes = {}

        class << self
          # The provider half of a model id: "claude-cli:claude-opus-5-5" is lane "claude-cli".
          def lane_of(model) = model.to_s.split(":", 2).first.to_s.then { |lane| lane.empty? ? ANY : lane }

          def silent?(lane = ANY)
            sync { (@lanes[lane] || {}).fetch(:silent_until, 0.0) > now }
          end

          # True only on the call that trips the lane, so the caller says it once.
          def record(answered, lane = ANY, reason: nil)
            sync do
              next clear(lane) if answered

              state = (@lanes[lane] ||= { failures: 0, silent_until: 0.0 })
              state[:reason] = reason.to_s.strip unless reason.to_s.strip.empty?
              state[:failures] += 1
              next false if state[:failures] < SILENT_AFTER

              state[:silent_until] = now + SILENCE_COOLOFF_S
              state[:failures] = 0
              true
            end
          end

          # Silent from failures, or dead because its provider said the quota is spent.
          def refuses?(model) = silent?(lane_of(model)) || Master::Io::LaneQuota.dead?(model)

          # A lane that is down says why and when it is back; otherwise the silence message.
          def refusal(model)
            lane = lane_of(model)
            return message(lane) if silent?(lane)

            Master::Io::LaneQuota.report.find { |row| row.start_with?("#{lane}: ") } || "#{lane}: dead (quota)"
          end

          def message(lane = ANY)
            said = sync { @lanes.dig(lane, :reason) }
            "no #{lane} answer in #{SILENT_AFTER} calls in a row; #{lane} is skipped for " \
              "#{SILENCE_COOLOFF_S / 60} minutes#{say(said)}. /model list says what each lane needs."
          end

          private

          def say(reason) = reason ? " (last: #{reason.lines.first.to_s.strip[0, 200]})" : ""

          def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          def clear(lane)
            @lanes.delete(lane)
            false
          end

          def sync(&) = @mutex.synchronize(&)
        end
      end
    end
  end
end
