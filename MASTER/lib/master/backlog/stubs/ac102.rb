# frozen_string_literal: true
# TODO artifact AC102: Retire /critique as separate command: fold into /review — /review already calls deliberation; /critique is a subset; rem
module Master
  module Backlog
    module Stubs
      module AC
        class AC102
          ID = "AC102".freeze
          DESCRIPTION = "Retire /critique as separate command: fold into /review — /review already calls deliberation; /critique is a subset; remove the distinction".freeze
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
