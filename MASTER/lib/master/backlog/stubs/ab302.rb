# frozen_string_literal: true
# TODO artifact AB302: GUARD_CLAUSE: message says "extract to guard clause" but the detection regex matches `def … if … else` — it fires on cor
module Master
  module Backlog
    module Stubs
      module AB
        class AB302
          ID = "AB302".freeze
          DESCRIPTION = "GUARD_CLAUSE: message says \"extract to guard clause\" but the detection regex matches `def … if … else` — it fires on correct guard clauses too if they're nested; refine regex".freeze
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
