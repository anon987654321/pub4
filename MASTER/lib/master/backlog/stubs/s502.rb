# frozen_string_literal: true
# TODO artifact S502: Conflict rule: "clarity conflicts with simplicity → favor clarity" — when both fire, suppress simplicity finding
module Master
  module Backlog
    module Stubs
      module S
        class S502
          ID = "S502".freeze
          DESCRIPTION = "Conflict rule: \"clarity conflicts with simplicity → favor clarity\" — when both fire, suppress simplicity finding".freeze
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
