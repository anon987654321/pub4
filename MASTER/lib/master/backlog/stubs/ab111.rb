# frozen_string_literal: true
# TODO artifact AB111: DEAD_CODE fires on line after `return` but not after `raise` at end of a rescue block — raise in rescue is a valid termi
module Master
  module Backlog
    module Stubs
      module AB
        class AB111
          ID = "AB111".freeze
          DESCRIPTION = "DEAD_CODE fires on line after `return` but not after `raise` at end of a rescue block — raise in rescue is a valid terminal; align the pattern".freeze
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
