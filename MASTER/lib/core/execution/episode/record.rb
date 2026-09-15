# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Episode
        # An Episode is the immutable record of a single meaningful execution.
        # It is the "One Source of Truth" from which all representations derive.
  class Record
    attr_reader :id, :intent, :lifecycle, :events, :observations, :mutations, :verification, :truth, :outcome, :trace
    
    def initialize(id:, intent:)
      @id = id
      @intent = intent
      @lifecycle = []
      @events = []
      @observations = []
      @mutations = []
      @verification = []
      @truth = {}
      @outcome = :pending
      @trace = []
    end
    
    def record_trace_entry(entry)
      @trace << entry
    end

          def record_event(event)
            @events << event
          end

          def record_observation(obs)
            @observations << obs
          end

          def record_mutation(mutation)
            @mutations << mutation
          end

          def record_verification(verif)
            @verification << verif
          end

          def set_truth(key, value)
            @truth[key] = value
          end

          def finalize(outcome)
            @outcome = outcome
          end

    def to_h
      {
        id: @id,
        intent: @intent,
        lifecycle: @lifecycle,
        events: @events,
        observations: @observations,
        mutations: @mutations,
        verification: @verification,
        truth: @truth,
        outcome: @outcome,
        trace: @trace.map(&:to_h)
      }
    end

        end
      end
    end
  end
end
