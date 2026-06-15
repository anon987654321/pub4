# frozen_string_literal: true
# TODO artifact R403: Proposals should be ranked by (confidence × impact) not just weight
module Master
  module Backlog
    module Stubs
      module R
        class R403
          ID = "R403".freeze
          DESCRIPTION = "Proposals should be ranked by (confidence × impact) not just weight".freeze
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
