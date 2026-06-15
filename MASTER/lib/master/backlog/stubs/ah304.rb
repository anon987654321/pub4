# frozen_string_literal: true
# TODO artifact AH304: Contradiction detection: when a new rule would conflict with an existing one, surface the conflict before registering
module Master
  module Backlog
    module Stubs
      module AH
        class AH304
          ID = "AH304".freeze
          DESCRIPTION = "Contradiction detection: when a new rule would conflict with an existing one, surface the conflict before registering".freeze
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
