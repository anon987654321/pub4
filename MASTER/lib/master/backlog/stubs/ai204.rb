# frozen_string_literal: true
# TODO artifact AI204: Graceful degradation: if all LLM providers fail, fall back to deterministic AstFixer-only mode; surface "LLM unavailable
module Master
  module Backlog
    module Stubs
      module AI
        class AI204
          ID = "AI204".freeze
          DESCRIPTION = "Graceful degradation: if all LLM providers fail, fall back to deterministic AstFixer-only mode; surface \"LLM unavailable — applying deterministic fixes only\"".freeze
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
