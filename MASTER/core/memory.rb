# frozen_string_literal: true

module Master::Core
  # Memory — the record. Holds the conversation the model sees and the evidence
  # the Constitution checks. Compaction is turn-aware: it summarises the oldest
  # turns and keeps the recent ones whole, never orphaning an observation from
  # the effect that produced it.
  #
  # This is where the old trace/, history/, and scope/ collapse to.
  class Memory
    Entry = Data.define(:role, :text)

    # What counts as proof, and how much of it ends the turn. This is the one
    # Ruby source for the core's evidence policy; the Model's prompt is built
    # from it (no restated numbers) and a test pins it to data/rules.yml, whose
    # evidence_scoring the lib spine still reads until that spine is severed.
    SCORING = {
      test_pass: 35,
      scan_clean: 25,
      code_review: 20,
      log_analysis: 10,
      profiling_data: 10
    }.freeze
    PASS_THRESHOLD = 80

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

    def initialize(budget: self.class.host_budget, summarize: ->(dropped) { "[#{dropped.length} earlier steps summarised]" })
      @entries = []
      @budget = budget
      @summarize = summarize
      @evidence = []
    end

    def note(kind, text)
      @entries << Entry.new(role: :note, text: "#{kind}: #{text}")
      self
    end

    def record(effect, observation)
      @entries << Entry.new(role: :act, text: effect.to_s)
      @entries << Entry.new(role: :obs, text: observation.to_s)
      record_evidence(effect, observation)
      self
    end

    def evidence_score = @evidence.select(&:ok).sum(&:score)
    def proved? = evidence_score >= PASS_THRESHOLD

    def record_evidence(effect, observation)
      return unless effect.verb == :exec && observation.ok?

      kind = effect.args[:evidence]&.to_sym
      score = SCORING.fetch(kind, 0)
      @evidence << Evidence.new(kind:, ok: true, score:, detail: observation.message, at: Time.now.utc) if score.positive?
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
        break if total >= @budget && e.role == :note # cut on a turn-ish boundary

        keep.unshift(e)
        total += e.text.length
      end
      dropped = @entries[0...(@entries.length - keep.length)]
      return if dropped.empty?

      @entries = [Entry.new(role: :note, text: @summarize.call(dropped)), *keep]
    end
  end
end