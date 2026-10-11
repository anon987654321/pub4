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

        class << self
          def call_timeout_s = positive("MASTER_COUNCIL_CALL_TIMEOUT_S", CALL_TIMEOUT_S)

          def pass_budget_s = positive("MASTER_COUNCIL_PASS_BUDGET_S", PASS_BUDGET_S)

          # MASTER_FIX_COUNCIL=0 turns the council off inside /fix: fixes only.
          def council_enabled? = ENV.fetch("MASTER_FIX_COUNCIL", "1") != "0"

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

          # The deadline for one call: the dispatcher's own, tightened inside a council.
          def call_deadline(default)
            return default unless active?

            [default, call_timeout_s, [remaining, 1.0].max].min
          end

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
