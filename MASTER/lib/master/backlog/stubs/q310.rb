# frozen_string_literal: true
# TODO artifact Q310: /rules list — show all registered Rule subclasses with their IDs and severity
module Master
  module Backlog
    module Stubs
      module Q
        class Q310
          ID = "Q310".freeze
          DESCRIPTION = "/rules list — show all registered Rule subclasses with their IDs and severity".freeze
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
