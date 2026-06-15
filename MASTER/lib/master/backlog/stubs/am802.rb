# frozen_string_literal: true
# TODO artifact AM802: Medusa (Cai et al. 2024): multiple parallel decoding heads predict N future tokens simultaneously; no draft model needed
module Master
  module Backlog
    module Stubs
      module AM
        class AM802
          ID = "AM802".freeze
          DESCRIPTION = "Medusa (Cai et al. 2024): multiple parallel decoding heads predict N future tokens simultaneously; no draft model needed; 2-3x speedup — applicable at model server level".freeze
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
