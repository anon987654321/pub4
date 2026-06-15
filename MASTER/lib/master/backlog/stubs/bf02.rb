# frozen_string_literal: true
# TODO artifact BF02: Prune redundant `return` keywords from terminal expressions in lambda blocks.
module Master
  module Backlog
    module Stubs
      module BF
        class BF02
          ID = "BF02".freeze
          DESCRIPTION = "Prune redundant `return` keywords from terminal expressions in lambda blocks.".freeze
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
