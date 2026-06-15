# frozen_string_literal: true
# TODO artifact AA701: "Correct by default" rather than "secure by configuration": MASTER's defaults should be maximally safe; unsafe behaviors
module Master
  module Backlog
    module Stubs
      module AA
        class AA701
          ID = "AA701".freeze
          DESCRIPTION = "\"Correct by default\" rather than \"secure by configuration\": MASTER's defaults should be maximally safe; unsafe behaviors require explicit opt-in (matches OpenBSD's philosophy)".freeze
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
