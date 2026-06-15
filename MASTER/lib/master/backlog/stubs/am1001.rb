# frozen_string_literal: true
# TODO artifact AM1001: HyDE (Gao et al. 2022): Hypothetical Document Embeddings — generate hypothetical answer, embed it, retrieve documents si
module Master
  module Backlog
    module Stubs
      module AM
        class AM1001
          ID = "AM1001".freeze
          DESCRIPTION = "HyDE (Gao et al. 2022): Hypothetical Document Embeddings — generate hypothetical answer, embed it, retrieve documents similar to hypothetical answer rather than query — improves recall for ambiguous queries".freeze
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
