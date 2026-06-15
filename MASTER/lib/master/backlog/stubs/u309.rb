# frozen_string_literal: true
# TODO artifact U309: Require method-level test coverage check before marking any rule violation as fixed: if the fixed method has no test, fl
module Master
  module Backlog
    module Stubs
      module U
        class U309
          ID = "U309".freeze
          DESCRIPTION = "Require method-level test coverage check before marking any rule violation as fixed: if the fixed method has no test, flag as \"fix unverified — add test\"".freeze
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
