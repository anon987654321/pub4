# frozen_string_literal: true
# TODO artifact AB306: EXPLICIT rule (B06): "detect implicit requires, implicit return types, magic coupling" — three completely different conc
module Master
  module Backlog
    module Stubs
      module AB
        class AB306
          ID = "AB306".freeze
          DESCRIPTION = "EXPLICIT rule (B06): \"detect implicit requires, implicit return types, magic coupling\" — three completely different concerns bundled; split into ExplicitRequiresRule, MethodMissingRule, AutoloadRule".freeze
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
