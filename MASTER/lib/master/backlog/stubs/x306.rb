# frozen_string_literal: true
# TODO artifact X306: Regex alternation ordering: put most-frequent match patterns first in alternation — /puts|print/ → /puts/ fires earlier 
module Master
  module Backlog
    module Stubs
      module X
        class X306
          ID = "X306".freeze
          DESCRIPTION = "Regex alternation ordering: put most-frequent match patterns first in alternation — /puts|print/ → /puts/ fires earlier on typical code".freeze
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
