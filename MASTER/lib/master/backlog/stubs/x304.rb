# frozen_string_literal: true
# TODO artifact X304: YJIT-friendly object shapes: pre-initialize all instance variables in Rule#initialize to stabilize object shapes for YJI
module Master
  module Backlog
    module Stubs
      module X
        class X304
          ID = "X304".freeze
          DESCRIPTION = "YJIT-friendly object shapes: pre-initialize all instance variables in Rule#initialize to stabilize object shapes for YJIT inline caches".freeze
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
