# frozen_string_literal: true
# TODO artifact AC408: Remove max_new_violations: 0 from fix_validation — this is correct behavior; make it invariant (not configurable)
module Master
  module Backlog
    module Stubs
      module AC
        class AC408
          ID = "AC408".freeze
          DESCRIPTION = "Remove max_new_violations: 0 from fix_validation — this is correct behavior; make it invariant (not configurable)".freeze
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
