# frozen_string_literal: true

require "securerandom"

module Master::Core::Execution

  # StructuralTrace — a non-linear record of an agent's reasoning and action.
  #
  # Unlike a simple transcript, a trace links every effect to the
  # observation and reasoning that triggered it. This is the primary
  # defense against "simulation" (where a model claims a result without
  # actually executing the tool).
  class StructuralTrace
    Entry = Data.define(:id, :role, :intent, :effect, :observation, :evidence, :timestamp)

    attr_reader :entries

    def initialize
      @entries = []
    end

    # Records a completed turn in the trace.
    def record(role:, intent:, effect:, observation:, evidence: nil)
      entry = Entry.new(
        id: SecureRandom.hex(4),
        role: role,
        intent: intent,
        effect: effect,
        observation: observation,
        evidence: evidence,
        timestamp: Time.now
      )
      @entries << entry
      entry
    end

    # Returns the last recorded evidence for a specific role.
    def last_evidence_for(role)
      @entries.reverse.find { |e| e.role == role }&.evidence
    end

    # Verifies if the trace contains a continuous chain of evidence
    # for a specific goal.
    def verified_chain?(goal)
      return false if @entries.empty?
      @entries.all? { |e| e.evidence&.verified? }
    end

    def clear!
      @entries = []
    end
  end
end
