# frozen_string_literal: true
# TODO artifact O804: Open3.capture3 called with string args in several places — use array form to prevent shell injection
module Master
  module Backlog
    module Stubs
      module O
        class O804
          ID = "O804".freeze
          DESCRIPTION = "Open3.capture3 called with string args in several places — use array form to prevent shell injection".freeze
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
