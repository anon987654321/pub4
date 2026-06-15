# frozen_string_literal: true
# TODO artifact AE102: Convergence as invariant: the loop doesn't have an iteration limit — it runs until the scan result is identical to the p
module Master
  module Backlog
    module Stubs
      module AE
        class AE102
          ID = "AE102".freeze
          DESCRIPTION = "Convergence as invariant: the loop doesn't have an iteration limit — it runs until the scan result is identical to the previous scan result (fixed point); abort only on oscillation detection".freeze
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
