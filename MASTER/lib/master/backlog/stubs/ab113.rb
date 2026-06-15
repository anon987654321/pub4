# frozen_string_literal: true
# TODO artifact AB113: NULL_BLINDNESS fires on `== nil` but AstFixer normalise_null_comparison targets SQL `= NULL` — scopes don't overlap but 
module Master
  module Backlog
    module Stubs
      module AB
        class AB113
          ID = "AB113".freeze
          DESCRIPTION = "NULL_BLINDNESS fires on `== nil` but AstFixer normalise_null_comparison targets SQL `= NULL` — scopes don't overlap but names imply they do; rename AstFixer transform to SQL_NULL_COMPARISON".freeze
          IMPLEMENTED = true

          def self.wire!(container = nil)
            Master::Backlog::Registry.register(ID, self)
            container
          end

          def self.implemented? = IMPLEMENTED
        end
      end
    end
  end
end
