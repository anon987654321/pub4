# frozen_string_literal: true
# TODO artifact AC105: Retire /propose-tree as separate command: proposal tree surfaces automatically when idle >5 minutes or after session wit
module Master
  module Backlog
    module Stubs
      module AC
        class AC105
          ID = "AC105".freeze
          DESCRIPTION = "Retire /propose-tree as separate command: proposal tree surfaces automatically when idle >5 minutes or after session with violations — not on-demand".freeze
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
