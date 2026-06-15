# frozen_string_literal: true
# TODO artifact AC310: Remove explicit --fix flag from commands — always fix when fixable; show diff first; confirm only for destructive refact
module Master
  module Backlog
    module Stubs
      module AC
        class AC310
          ID = "AC310".freeze
          DESCRIPTION = "Remove explicit --fix flag from commands — always fix when fixable; show diff first; confirm only for destructive refactors".freeze
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
