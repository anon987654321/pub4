# frozen_string_literal: true
# TODO artifact S903: Fix validation: after applying fix, re-scan; if new violations introduced exceed max_new_violations: 0, rollback the fix
module Master
  module Backlog
    module Stubs
      module S
        class S903
          ID = "S903".freeze
          DESCRIPTION = "Fix validation: after applying fix, re-scan; if new violations introduced exceed max_new_violations: 0, rollback the fix".freeze
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
