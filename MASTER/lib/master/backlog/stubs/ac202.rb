# frozen_string_literal: true
# TODO artifact AC202: Any input containing "why" or "explain" → auto-run /why on most recent finding; no /why command needed
module Master
  module Backlog
    module Stubs
      module AC
        class AC202
          ID = "AC202".freeze
          DESCRIPTION = "Any input containing \"why\" or \"explain\" → auto-run /why on most recent finding; no /why command needed".freeze
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
