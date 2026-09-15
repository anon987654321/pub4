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

          def update(params)
            # Return a new State object (immutable)
            new_phase = params[:phase] || @phase
            new_focus = params[:focus] || @focus
            new_progress = params[:progress] || @progress
            new_risk = params[:risk] || @risk

            # Update grammar based on phase or focus
            new_grammar = if params.key?(:phase) || params.key?(:focus)
                            new_focus ? Grammar.for_target(new_focus) : Grammar.for_phase(new_phase)
                          else
                            @grammar
                          end
            
            # Update semantic field based on the new phase and target
            new_field = if params.key?(:phase) || params.key?(:focus) || params.key?(:progress) || params.key?(:risk)
                          SemanticField.derive(new_phase, new_focus, progress: new_progress, risk: new_risk)
                        else
                          @field
                        end

            self.class.new(
              phase: new_phase,
              activity: params[:activity] || @activity,
              attention: params[:attention] || @attention,
              progress: new_progress,
              risk: new_risk,
              severity: params[:severity] || @severity,
              focus: new_focus,
              grammar: new_grammar,
              field: new_field
            )
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
