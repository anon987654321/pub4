# frozen_string_literal: true
# TODO artifact AB110: KEYWORD_ARGS fires on `def foo(a, b, c)` but not on `def foo(a, b, c = nil)` — the presence of a default makes it a keyw
module Master
  module Backlog
    module Stubs
      module AB
        class AB110
          ID = "AB110".freeze
          DESCRIPTION = "KEYWORD_ARGS fires on `def foo(a, b, c)` but not on `def foo(a, b, c = nil)` — the presence of a default makes it a keyword-style arg; rule inconsistently exempts defaults".freeze
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
