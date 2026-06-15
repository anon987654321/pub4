# frozen_string_literal: true
# TODO artifact W102: Codify "exit codes carry meaning": scan violations = exit 1, internal errors = exit 2, LLM failure = exit 3 — wire to bi
module Master
  module Backlog
    module Stubs
      module W
        class W102
          ID = "W102".freeze
          DESCRIPTION = "Codify \"exit codes carry meaning\": scan violations = exit 1, internal errors = exit 2, LLM failure = exit 3 — wire to bin/cli; document in CONVENTIONS.md".freeze
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
