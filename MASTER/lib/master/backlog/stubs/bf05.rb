# frozen_string_literal: true
# TODO artifact BF05: Replace double-negative loops (`unless !condition`) with clean positive checking loops.
module Master
  module Backlog
    module Stubs
      module BF
        class BF05
          ID = "BF05".freeze
          DESCRIPTION = "Replace double-negative loops (`unless !condition`) with clean positive checking loops.".freeze
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
