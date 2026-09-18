# frozen_string_literal: true

module Master
  module Io
    # Constraint-Based Design & Music DSL
    #
    # Instead of predicting raw output values (which LLMs struggle with),
    # this DSL defines structural and relational constraints. 
    # A solver then resolves these constraints into concrete parameters.
    #
    # Example: "Constraint: Bass should be the root of the chord, 
    #           and the Kick should hit on the 1 and 3."
    module ConstraintDSL
      module_function

      # A Constraint is a rule about a relationship between two or more parameters.
      Constraint = Struct.new(:subject, :relation, :target, :weight, keyword_init: true)

      def parse_intent(text)
        # In a full implementation, this would be a specialized LLM prompt 
        # returning a JSON array of Constraints.
        # For the prototype, we use a simple keyword-based extractor.
        constraints = []
        
        if text.match?(/root of the chord/i)
          constraints << Constraint.new(subject: :bass, relation: :align, target: :root, weight: 1.0)
        end
        if text.match?(/hit on the 1 and 3/i)
          constraints << Constraint.new(subject: :kick, relation: :sync, target: [1, 3], weight: 1.0)
        end
        if text.match?(/golden ratio/i)
          constraints << Constraint.new(subject: :x_pos, relation: :ratio, target: 1.618, weight: 1.0)
        end
        
        constraints
      end

      # The Solver resolves constraints into a final parameter map.
      def resolve(constraints, base_params = {})
        resolved = base_params.dup
        
        constraints.each do |c|
          case c.relation
          when :align
            # Example: Bass aligns to Root
            resolved[c.subject] = resolved[c.target] || 0.0
          when :sync
            # Example: Kick syncs to beats [1, 3]
            resolved[c.subject] = c.target
          when :ratio
            # Example: x_pos is golden ratio of width
            resolved[c.subject] = (resolved[:width] || 100) * c.target
          end
        end
        
        resolved
      end
    end
  end
end
