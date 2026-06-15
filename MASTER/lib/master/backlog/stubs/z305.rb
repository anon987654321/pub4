# frozen_string_literal: true
# TODO artifact Z305: Normalize `raise` vs `fail`: pick one idiom per codebase — Jeremy Evans uses `raise` exclusively
module Master
  module Backlog
    module Stubs
      module Z
        class Z305
          ID = "Z305".freeze
          DESCRIPTION = "Normalize `raise` vs `fail`: pick one idiom per codebase — Jeremy Evans uses `raise` exclusively".freeze
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
