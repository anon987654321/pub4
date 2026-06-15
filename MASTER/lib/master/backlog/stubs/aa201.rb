# frozen_string_literal: true
# TODO artifact AA201: Immutable finding collections: Finding objects are mutated after creation (adding context, suggestion) — freeze after co
module Master
  module Backlog
    module Stubs
      module AA
        class AA201
          ID = "AA201".freeze
          DESCRIPTION = "Immutable finding collections: Finding objects are mutated after creation (adding context, suggestion) — freeze after construction; return new Finding for modifications".freeze
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
