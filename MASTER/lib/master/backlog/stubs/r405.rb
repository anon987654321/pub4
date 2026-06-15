# frozen_string_literal: true
# TODO artifact R405: Proposals should include a "reject" action that logs the rejection to learnings for future tuning
module Master
  module Backlog
    module Stubs
      module R
        class R405
          ID = "R405".freeze
          DESCRIPTION = "Proposals should include a \"reject\" action that logs the rejection to learnings for future tuning".freeze
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
