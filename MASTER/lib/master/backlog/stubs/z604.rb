# frozen_string_literal: true
# TODO artifact Z604: Replace `node.respond_to?(:child_nodes)` guard with `node.is_a?(Prism::Node)` — more precise, enables YJIT inline cache 
module Master
  module Backlog
    module Stubs
      module Z
        class Z604
          ID = "Z604".freeze
          DESCRIPTION = "Replace `node.respond_to?(:child_nodes)` guard with `node.is_a?(Prism::Node)` — more precise, enables YJIT inline cache hits".freeze
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
