# frozen_string_literal: true
# TODO artifact Z403: Replace `Array()` wrapping with explicit `.to_a` or `Array.wrap` — `Array(tags)` in RuleDSL is idiomatic but inconsisten
module Master
  module Backlog
    module Stubs
      module Z
        class Z403
          ID = "Z403".freeze
          DESCRIPTION = "Replace `Array()` wrapping with explicit `.to_a` or `Array.wrap` — `Array(tags)` in RuleDSL is idiomatic but inconsistent with rest of codebase".freeze
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
