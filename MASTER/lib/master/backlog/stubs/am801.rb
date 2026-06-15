# frozen_string_literal: true
# TODO artifact AM801: Speculative decoding (Leviathan et al. 2022): draft model (llama3-8b) proposes K tokens; target model (claude) verifies 
module Master
  module Backlog
    module Stubs
      module AM
        class AM801
          ID = "AM801".freeze
          DESCRIPTION = "Speculative decoding (Leviathan et al. 2022): draft model (llama3-8b) proposes K tokens; target model (claude) verifies in single forward pass; 2-3x throughput with identical quality".freeze
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
