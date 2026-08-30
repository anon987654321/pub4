# frozen_string_literal: true

require "monitor"
require_relative "../fix/constants"

module Master
  module Ground
    # The paid-provider limit gate, and the one surface anything downstream
    # asks about it.
    #
    # A spend limit is not a rate limit and not a broken key, and the three
    # want three different answers:
    #
    #   :available  spend the call.
    #   :exhausted  out of credit or over quota. Temporary — a monthly window
    #               rolls, a shared balance is topped up, a burst allowance
    #               refills — so stop hammering, then re-probe on a backoff.
    #   :refused    the key is bad, revoked, or unauthorized. Re-probing an
    #               unauthorized key is not waiting for anything, so this one
    #               stops until a human changes the key.
    #
    # Only :refused is a stop. Latching :exhausted for the process would turn a
    # ten-minute provider outage into a whole run of silently skipped work,
    # which is the same defect one level up from the one this file exists to
    # fix: deciding at minute one that a tier does not exist.
    #
    # Trip fast, re-probe soon. The wait comes from
    # FailureTaxonomy.backoff_seconds — the same capped exponential
    # Io::ReplicateClient retries on, so there is one backoff formula in the
    # tree — indexed by how many times the limit has been confirmed in a row.
    # First confirmation waits a second, the fourth waits eight, and it caps at
    # a minute, so a long gate picks the tier back up within a minute of the
    # limit lifting. A successful paid call clears the count.
    #
    # What this is NOT: a second per-model breaker. Ground::ModelSkipCache
    # already parks an individual dead endpoint so failover chains route around
    # it. This is the tier-level fact — "the semantic rules could not run, and
    # here is why" — which no per-model cache can answer, and which is the half
    # that otherwise reads as a clean bill of health.
    #
    # Downstream contract (the queryable surface, not the log line):
    #   QuotaGate.state          -> :available | :exhausted | :refused
    #   QuotaGate.blocked?       -> do not spend a paid call right now
    #   QuotaGate.tripped?       -> a limit was hit at any point this run
    #   QuotaGate.skipped(name)  -> record a tier that did not run because of it
    #   QuotaGate.skipped_tiers  -> those names, first-seen order
    #   QuotaGate.report         -> nil, or one line naming tier, cause and ETA
    #   QuotaGate.substitutions  -> [{from:, to:}] models that stood in
    #   QuotaGate.substitution_note -> nil, or one line naming those swaps
    #   QuotaGate.status         -> the same facts as a Hash, for a report object
    # A Result that carries this condition uses category :exhausted, and a
    # stage that ran as a subprocess exits QuotaGate::INCONCLUSIVE_EXIT.
    module QuotaGate
      CATEGORY = :exhausted
      # The exit status a stage takes when a paid tier could not run. Third
      # state, not a failure and not a pass: RAILS/gates/runner.rb already
      # spends 3 on "inconclusive — nothing measured", and a chain that folds
      # "could not run" into either of the other two is the defect this whole
      # file guards.
      INCONCLUSIVE_EXIT = 3
      LOCK = Monitor.new
      # Hard refusals. A key that is rejected is not a balance that refills, so
      # these do not re-probe.
      REFUSED_RE = /unauthorized|invalid[ _-]?api[ _-]?key|revoked|forbidden|\b401\b|\b403\b/i

      @state = :available
      @resume_at = nil
      @confirmations = 0
      @source = nil
      @model = nil
      @message = nil
      @skipped = []
      @substitutions = []

      module_function

      # Whether this message means a spend limit, per the shared taxonomy. No
      # second copy of the patterns lives here.
      def exhaustion?(message)
        FailureTaxonomy.exhausted?(message)
      rescue StandardError
        # STUDIO/repligen and STUDIO/lora load Io::ReplicateClient standalone,
        # without the runtime that gives FailureTaxonomy its rules.yml. The
        # gate still has to answer there, so it falls back to the pattern the
        # taxonomy would have reached for anyway.
        Master::Fix::Constants::EXHAUSTED_RE.match?(message.to_s)
      end

      def refusal?(message) = REFUSED_RE.match?(message.to_s)

      # Record a paid call that failed for a limit, after its own failover
      # chain had its turn. Returns true when this call is the one that closed
      # the gate — the caller that gets true is the only one that needs to say
      # so, which is what turns N identical persona_error lines into one.
      def trip!(source:, message:, model: nil)
        first = LOCK.synchronize do
          was_open = !blocked_now?
          @state = refusal?(message) ? :refused : :exhausted
          @confirmations += 1
          @resume_at = @state == :refused ? nil : now + FailureTaxonomy.backoff_seconds(@confirmations - 1)
          @source = source.to_s
          @model = model.to_s
          @message = message.to_s.strip
          was_open
        end
        announce if first
        first
      end

      # Classify and trip in one step, for a rescue that does not otherwise
      # care what it caught. True when the error was a limit, whether or not
      # this call was the one that tripped it.
      def trip_if_limited(source:, message:, model: nil)
        return false unless exhaustion?(message) || refusal?(message)

        trip!(source:, message:, model:)
        true
      end

      # A paid call came back. The limit lifted, so drop the backoff entirely
      # rather than decaying it — the next outage should trip fast again.
      def clear!
        LOCK.synchronize do
          return false if @state == :available

          @state = :available
          @resume_at = nil
          @confirmations = 0
          true
        end
      end

      def state = LOCK.synchronize { @state }

      def blocked? = LOCK.synchronize { blocked_now? }

      def tripped? = LOCK.synchronize { @confirmations.positive? }

      # 0 when a probe is due now, nil when nothing will re-probe (:refused).
      def seconds_until_probe
        LOCK.synchronize do
          next nil if @state == :refused
          next 0 unless blocked_now?

          (@resume_at - now).ceil
        end
      end

      # Record a tier that did not run because the gate was closed. Idempotent:
      # the semantic rules ask once per file, and that is one fact.
      def skipped(tier)
        name = tier.to_s
        LOCK.synchronize { @skipped << name unless @skipped.include?(name) }
        name
      end

      def skipped_tiers = LOCK.synchronize { @skipped.dup }

      # A call that answered on a different provider than the one it was routed
      # to. A council that quietly changes model is not reviewing the same way
      # twice, so the swap belongs in the record beside the verdict — and a
      # council that runs on a substitute is still far better than one that
      # does not run.
      def substituted(from:, to:)
        swap = { from: from.to_s, to: to.to_s }
        LOCK.synchronize { @substitutions << swap unless @substitutions.include?(swap) }
        swap
      end

      def substitutions = LOCK.synchronize { @substitutions.dup }

      # Separate from #report, not folded into it: the good case is a swap that
      # worked, where nothing tripped and #report is correctly nil. That run
      # still did not review on the model it says it routed to, and a caller
      # that only printed #report would never mention it.
      def substitution_note
        swaps = substitutions
        return nil if swaps.empty?

        "SUBSTITUTED #{swaps.map { |s| "#{s[:from]} -> #{s[:to]}" }.join(", ")}"
      end

      # nil when nothing went wrong, so a caller can append it unconditionally
      # and a clean run stays clean.
      def report
        LOCK.synchronize do
          next nil if @confirmations.zero?

          tiers = @skipped.empty? ? "paid model calls" : @skipped.join(", ")
          "SKIPPED #{tiers} — #{cause_now} on #{@model.to_s.empty? ? "the routed model" : @model} " \
            "via #{@source} (#{@message}); #{recovery_now}"
        end
      end

      def status
        LOCK.synchronize do
          {
            category: CATEGORY,
            state: @state,
            tripped: @confirmations.positive?,
            confirmations: @confirmations,
            blocked: blocked_now?,
            source: @source,
            model: @model,
            message: @message,
            skipped_tiers: @skipped.dup,
            substitutions: @substitutions.dup,
            seconds_until_probe: @state == :refused ? nil : (blocked_now? ? (@resume_at - now).ceil : 0),
          }
        end
      end

      def reset!
        LOCK.synchronize do
          @state = :available
          @resume_at = nil
          @confirmations = 0
          @source = nil
          @model = nil
          @message = nil
          @skipped = []
          @substitutions = []
        end
      end

      def blocked_now? = @state == :refused || (!@resume_at.nil? && now < @resume_at)

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def cause_now = @state == :refused ? "provider refused the key" : "provider spend limit"

      def recovery_now
        return "no re-probe: a refused key needs a human, not a wait" if @state == :refused
        return "re-probing now" unless blocked_now?

        "re-probing in #{(@resume_at - now).ceil}s"
      end

      def announce
        Master::Trace::Dmesg.status(
          "quota0",
          "#{cause_now} via #{@source} — pausing paid calls, #{recovery_now}: #{@message}",
        )
      rescue StandardError => e
        # A standalone load has no Dmesg. The fact still has to reach someone.
        warn("quota0: #{cause_now} via #{@source}: #{@message} (dmesg unavailable: #{e.class})")
      end

      private_class_method :blocked_now?, :now, :cause_now, :recovery_now, :announce
    end
  end
end
