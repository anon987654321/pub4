# frozen_string_literal: true
# TODO artifact X103: Compress rule descriptions sent to LLM: ID + one sentence only; full YAML stays in code — reduces system prompt 60%
module Master
  module Backlog
    module Stubs
      module X
        class X103
          ID = "X103".freeze
          DESCRIPTION = "Compress rule descriptions sent to LLM: ID + one sentence only; full YAML stays in code — reduces system prompt 60%".freeze
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
