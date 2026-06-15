# frozen_string_literal: true
# TODO artifact AB109: GUARD_CLAUSE and NESTING_DEPTH both fire on deeply nested if/else — GUARD_CLAUSE fires at def level, NESTING_DEPTH at >4
module Master
  module Backlog
    module Stubs
      module AB
        class AB109
          ID = "AB109".freeze
          DESCRIPTION = "GUARD_CLAUSE and NESTING_DEPTH both fire on deeply nested if/else — GUARD_CLAUSE fires at def level, NESTING_DEPTH at >4 levels; they can both fire on same method; suppress one".freeze
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
