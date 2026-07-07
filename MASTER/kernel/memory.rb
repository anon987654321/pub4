# frozen_string_literal: true

module Master::Kernel
  # Memory — the record. Holds the conversation the model sees and the evidence
  # the Constitution checks. Compaction is turn-aware: it summarises the oldest
  # turns and keeps the recent ones whole, never orphaning an observation from
  # the effect that produced it.
  #
  # This is where the old trace/, history/, and scope/ collapse to.
  class Memory
    Entry = Data.define(:role, :text)

    def initialize(budget: 24_000, summarize: ->(dropped) { "[#{dropped.length} earlier steps summarised]" })
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
    def proved? = evidence_score >= 80

    def record_evidence(effect, observation)
      return unless effect.verb == :exec && observation.ok?

      kind = effect.args[:evidence]&.to_sym
      score = {
        test_pass: 35,
        scan_clean: 25,
        code_review: 20,
        log_analysis: 10,
        profiling_data: 10
      }.fetch(kind, 0)
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