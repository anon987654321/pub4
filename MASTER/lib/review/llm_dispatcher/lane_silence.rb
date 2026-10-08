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
      # After SILENT_AFTER consecutive failures with no answer in between, the
      # door refuses for SILENCE_COOLOFF_S and says so once. One success from
      # any lane clears it, so a provider coming back needs no restart. The
      # refusal is :no_api_key, which callers already treat as permanent and
      # skip rather than retry.
      #
      # Process-wide, and its own module because the state is: the dispatcher is
      # built per session and the lanes are shared by all of them.
      module LaneSilence
        SILENT_AFTER = 12
        SILENCE_COOLOFF_S = 300

        @mutex = Mutex.new
        @consecutive_failures = 0
        @silent_until = 0.0

        class << self
          def silent?
            sync { @silent_until > Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          end

          # True only on the call that trips it, so the caller says it once.
          def record(answered)
            sync do
              next clear if answered

              @consecutive_failures += 1
              next false if @consecutive_failures < SILENT_AFTER

              @silent_until = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SILENCE_COOLOFF_S
              @consecutive_failures = 0
              true
            end
          end

          def message
            "no lane answered #{SILENT_AFTER} calls in a row; model work is skipped for " \
              "#{SILENCE_COOLOFF_S / 60} minutes. /model list says what each lane needs."
          end

          private

          def clear
            @consecutive_failures = 0
            @silent_until = 0.0
            false
          end

          def sync(&) = @mutex.synchronize(&)
        end
      end
    end
  end
end
