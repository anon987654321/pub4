# frozen_string_literal: true
# TODO artifact AK301: Speculative decoding: use small draft model to propose tokens; large model verifies in parallel — 2-3x throughput withou
module Master
  module Backlog
    module Stubs
      module AK
        class AK301
          ID = "AK301".freeze
          DESCRIPTION = "Speculative decoding: use small draft model to propose tokens; large model verifies in parallel — 2-3x throughput without quality loss".freeze
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
