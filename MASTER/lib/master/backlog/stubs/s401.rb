# frozen_string_literal: true
# TODO artifact S401: Implement scan profiles: quick (core axioms only), full (all rules), axioms_only, solid_focus (SOLID + axioms), critical
module Master
  module Backlog
    module Stubs
      module S
        class S401
          ID = "S401".freeze
          DESCRIPTION = "Implement scan profiles: quick (core axioms only), full (all rules), axioms_only, solid_focus (SOLID + axioms), critical (veto-severity only)".freeze
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
