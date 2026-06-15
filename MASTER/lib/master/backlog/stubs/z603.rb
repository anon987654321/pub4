# frozen_string_literal: true
# TODO artifact Z603: Remove redundant `.compact` after `node.child_nodes` — child_nodes already returns no nils in modern Prism
module Master
  module Backlog
    module Stubs
      module Z
        class Z603
          ID = "Z603".freeze
          DESCRIPTION = "Remove redundant `.compact` after `node.child_nodes` — child_nodes already returns no nils in modern Prism".freeze
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
