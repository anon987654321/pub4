# frozen_string_literal: true

module Master
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
      @proved = false
    end

    def note(kind, text)
      @entries << Entry.new(role: :note, text: "#{kind}: #{text}")
      self
    end

    # Record an effect and what the world reported. A passing test/scan flips the
    # evidence flag the :evidence_for_done rule depends on.
    def record(effect, observation)
      @entries << Entry.new(role: :act, text: effect.to_s)
      @entries << Entry.new(role: :obs, text: observation.to_s)
      @proved = true if observation.ok && effect.verb == :exec
      self
    end

    def proved? = @proved

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
