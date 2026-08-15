# frozen_string_literal: true

module Master::Core
  # Memory — the record. Holds the conversation the model sees, compacted to a
  # budget. Compaction is turn-aware: it summarises the oldest turns and keeps
  # the recent ones whole, never orphaning an observation from the effect that
  # produced it.
  #
  # This is where the old trace/, history/, and scope/ collapse to.
  #
  # What it no longer holds is Proof — the evidence ledger and the risk gates,
  # which moved to lib/core/proof.rb on 2026-08-12. Memory answers what was
  # said; Proof answers whether it was enough. Reach the second through
  # `memory.proof`, deliberately rather than through forwarding methods: a
  # delegator would have kept the public count where it was and hidden the seam
  # that the count existed to point at.
  class Memory
    Entry = Data.define(:role, :text)

    # Context budget in characters. A ~1GB OpenBSD VPS cannot hold a generous
    # transcript alongside an LLM call without the OOM-killer stepping in, so on a
    # constrained host the budget shrinks and compaction runs sooner. This is the
    # whole of the old HostBudget the core needs — the guard rides on Memory's
    # existing compaction, so the Fold gains no new logic. The rest of HostBudget
    # (TTS toggles, pid reaping, shell tips) is CLI accretion that dies with lib.
    GENEROUS_BUDGET = 24_000
    CONSTRAINED_BUDGET = 8_000
    CONSTRAINED_MB = 1_100

    def self.budget_for(total_mb)
      total_mb && total_mb <= CONSTRAINED_MB ? CONSTRAINED_BUDGET : GENEROUS_BUDGET
    end

    def self.host_budget = budget_for(host_memory_mb)

    # Physical memory in MB, or nil when it cannot be told (then we stay generous).
    def self.host_memory_mb
      @host_memory_mb ||= detect_host_memory_mb
    end

    def self.detect_host_memory_mb
      if RUBY_PLATFORM.include?("openbsd")
        bytes = `sysctl -n hw.physmem 2>/dev/null`.to_i
        return bytes / 1_048_576 if bytes.positive?
      end
      if File.readable?("/proc/meminfo")
        kb = File.readlines("/proc/meminfo").find { |l| l.start_with?("MemTotal:") }&.split&.fetch(1, nil).to_i
        return kb / 1024 if kb&.positive?
      end
      nil
    rescue StandardError
      nil
    end

    # Only host_memory_mb calls it. `private` cannot reach a `def self.` — see
    # CodeMetrics.public_method_count and DEBT.md, "The fold spine had never been
    # scanned".
    private_class_method :detect_host_memory_mb

    attr_reader :proof

    def initialize(budget: self.class.host_budget, summarize: ->(dropped) { "[#{dropped.length} earlier steps summarised]" }, risk: :low)
      @entries = []
      @budget = budget
      @summarize = summarize
      @proof = Proof.new(risk:)
    end

    def note(kind, text)
      @entries << Entry.new(role: :note, text: "#{kind}: #{text}")
      self
    end

    def record(effect, observation)
      @entries << Entry.new(role: :act, text: effect.to_s)
      @entries << Entry.new(role: :obs, text: observation.to_s)
      @proof.record_evidence(effect, observation)
      @proof.mark_council_pass!(detail: observation.message) if effect.verb == :critique && observation.ok?
      self
    end

    # The context the model proposes against — compacted to the budget.
    def context
      compact if size > @budget
      @entries
    end

    private

    def size = @entries.sum { |e| e.text.length }

    def compact
      keep = []
      total = 0
      @entries.reverse_each do |e|
        # Cut when the next piece would blow the budget. Waiting for a :note
        # after the budget is already exceeded never fires: Fold writes one
        # note (the goal) then only :act/:obs, so the only note is the oldest
        # entry and compact kept every act/obs and dropped only the goal.
        break if !keep.empty? && (total + e.text.length) > @budget

        keep.unshift(e)
        total += e.text.length
      end
      dropped = @entries[0...(@entries.length - keep.length)]
      return if dropped.empty?

      @entries = [Entry.new(role: :note, text: @summarize.call(dropped)), *keep]
    end
  end
end
