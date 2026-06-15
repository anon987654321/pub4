# frozen_string_literal: true
# TODO artifact AM1002: ColBERT v2 (Santhanam et al. 2021): late-interaction retrieval model — token-level similarity across query and document;
module Master
  module Backlog
    module Stubs
      module AM
        class AM1002
          ID = "AM1002".freeze
          DESCRIPTION = "ColBERT v2 (Santhanam et al. 2021): late-interaction retrieval model — token-level similarity across query and document; better than bi-encoder for code retrieval".freeze
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
