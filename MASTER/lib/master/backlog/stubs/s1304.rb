# frozen_string_literal: true
# TODO artifact S1304: Recency bias guard: don't weight most-recent violation above earlier ones when prioritizing fix order — use severity × f
module Master
  module Backlog
    module Stubs
      module S
        class S1304
          ID = "S1304".freeze
          DESCRIPTION = "Recency bias guard: don't weight most-recent violation above earlier ones when prioritizing fix order — use severity × frequency × age".freeze
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
