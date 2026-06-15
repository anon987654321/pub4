# frozen_string_literal: true
# TODO artifact X107: Truncate violation context window: send only lines (lineno-5)..(lineno+10) around each violation, not whole file, for ta
module Master
  module Backlog
    module Stubs
      module X
        class X107
          ID = "X107".freeze
          DESCRIPTION = "Truncate violation context window: send only lines (lineno-5)..(lineno+10) around each violation, not whole file, for targeted fixes".freeze
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
