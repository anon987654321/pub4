# frozen_string_literal: true

require_relative "grammar"
require_relative "semantic_field"

module Master
  module Core
    module Execution
      module Presence
        # Presence is the composition layer for all sensory outputs.
        # It transforms raw execution events into a semantic state.
        class State
          attr_reader :phase, :activity, :attention, :progress, :risk, :severity, :focus, :grammar, :field
          
          def initialize(phase: :idle, activity: 0.0, attention: 0.0, progress: 0.0, risk: 0.0, severity: :normal, focus: nil, grammar: nil, field: nil)
            @phase = phase
            @activity = activity
            @attention = attention
            @progress = progress
            @risk = risk
            @severity = severity
            @focus = focus
            @grammar = grammar || Grammar.for_phase(phase)
            @field = field || SemanticField.derive(phase, focus, progress: progress, risk: risk)
          end

          # A new State, never a mutated one. Grammar follows a changed phase or
          # focus, and the semantic field follows any of the four it derives from.
          def update(params)
            fields = to_h.except(:grammar, :field).merge(params.compact.slice(*to_h.keys))
            fields[:grammar] = grammar_after(params, fields)
            fields[:field] = field_after(params, fields)
            self.class.new(**fields)
          end

          def grammar_after(params, fields)
            return @grammar unless params.key?(:phase) || params.key?(:focus)

            fields[:focus] ? Grammar.for_target(fields[:focus]) : Grammar.for_phase(fields[:phase])
          end

          def field_after(params, fields)
            return @field unless %i[phase focus progress risk].any? { |key| params.key?(key) }

            SemanticField.derive(fields[:phase], fields[:focus], progress: fields[:progress], risk: fields[:risk])
          end

          def to_h
            {
              phase: @phase,
              activity: @activity,
              attention: @attention,
              progress: @progress,
              risk: @risk,
              severity: @severity,
              focus: @focus,
              grammar: @grammar,
              field: @field
            }
          end
        end
      end
    end
  end
end
