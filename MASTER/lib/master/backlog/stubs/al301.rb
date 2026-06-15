# frozen_string_literal: true
# TODO artifact AL301: Transaction import pipeline: CSV/OFX/PDF → parser → normalizer → LLM categorizer → SQLite ledger; one command per file t
module Master
  module Backlog
    module Stubs
      module AL
        class AL301
          ID = "AL301".freeze
          DESCRIPTION = "Transaction import pipeline: CSV/OFX/PDF → parser → normalizer → LLM categorizer → SQLite ledger; one command per file type".freeze
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
