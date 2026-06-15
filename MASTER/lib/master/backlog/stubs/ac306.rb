# frozen_string_literal: true
# TODO artifact AC306: Remove all scan profile flags (--profile quick, --profile critical) — always full scan; profiling was a performance work
module Master
  module Backlog
    module Stubs
      module AC
        class AC306
          ID = "AC306".freeze
          DESCRIPTION = "Remove all scan profile flags (--profile quick, --profile critical) — always full scan; profiling was a performance workaround".freeze
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
