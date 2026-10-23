# frozen_string_literal: true

module Master
  module Review
    class LLMDispatcher
      # The wall clock of one council. A /fix run sat 39 minutes in its first
      # council, waiting 186 seconds per call on a free model, and never reached
      # a file. The council is advisory; this is what stops it from being the
      # run. Inside `within` every model call is capped at call_timeout_s and
      # refused once the budget is spent, so whatever answered by then is what
      # the pass uses. `cancel!` ends an advisory phase early (the stall watchdog
      # calls it) and `reset_cancel!` lifts it when the next phase begins.
      #
      # Process-wide, because the council's persona threads do not inherit
      # thread-locals and /fix runs one council at a time, before its fixes.
      module PassClock
        CALL_TIMEOUT_S = 120
        PASS_BUDGET_S = 600

        @mutex = Mutex.new
        @deadline = nil
        @budget = nil
        @cancelled = nil
        @call_cap = nil

        class << self
          def call_timeout_s = positive("MASTER_COUNCIL_CALL_TIMEOUT_S", CALL_TIMEOUT_S)

          def pass_budget_s = positive("MASTER_COUNCIL_PASS_BUDGET_S", PASS_BUDGET_S)

          # The council is off inside /fix until MASTER_FIX_COUNCIL=1 or --critique asks for it: the run
          # ends with an offer to convene it on the result, so a council fault cannot cost a repair.
          def council_enabled?(env: ENV) = env["MASTER_FIX_COUNCIL"] == "1"

          def within(budget = nil)
            seconds = budget || pass_budget_s
            previous = sync { [@deadline, @budget] }
            sync { @deadline = now + seconds; @budget = seconds }
            yield
          ensure
            sync { @deadline, @budget = previous }
          end

          def active? = sync { !@deadline.nil? }

          def budget_s = sync { @budget }

          def remaining = sync { @deadline && [@deadline - now, 0.0].max }

          def expired? = sync { !@cancelled.nil? || (!@deadline.nil? && now >= @deadline) }

          def cancel!(reason) = sync { @cancelled = reason.to_s }

          def reset_cancel! = sync { @cancelled = nil }

          def cancelled? = sync { !@cancelled.nil? }

          # The deadline for one call: the dispatcher's own, under the run's cap, tightened inside a council.
          def call_deadline(default)
            capped = [default, sync { @call_cap }].compact.min
            return capped unless active?

            [capped, call_timeout_s, [remaining, 1.0].max].min
          end

          # A /fix run caps every model call below its stall window, so one slow call fails its file
          # and the pass moves on rather than the watchdog ending the run. Nil lifts the cap.
          def cap_calls!(seconds) = sync { @call_cap = seconds&.positive? ? seconds : nil }

          def call_cap = sync { @call_cap }

          def refusal
            "council deadline #{budget_s || "reached"}s spent, no further model calls this phase#{cancelled? ? " (#{sync { @cancelled }})" : ""}"
          end

          private

          def positive(name, default)
            value = Integer(ENV.fetch(name, default.to_s), exception: false)
            value&.positive? ? value : default
          end

          def sync(&) = @mutex.synchronize(&)

          def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
