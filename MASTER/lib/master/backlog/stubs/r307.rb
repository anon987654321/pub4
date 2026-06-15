# frozen_string_literal: true
# TODO artifact R307: Missing abstraction proposal: when same literal appears in 3+ files, propose extracting to a named constant or value obj
module Master
  module Backlog
    module Stubs
      module R
        class R307
          ID = "R307".freeze
          DESCRIPTION = "Missing abstraction proposal: when same literal appears in 3+ files, propose extracting to a named constant or value object".freeze
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
