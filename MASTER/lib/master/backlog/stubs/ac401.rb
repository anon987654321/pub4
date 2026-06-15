# frozen_string_literal: true
# TODO artifact AC401: Remove max_iterations: 10 limit — iterate until zero violations; the limit existed because old LLM calls were expensive,
module Master
  module Backlog
    module Stubs
      module AC
        class AC401
          ID = "AC401".freeze
          DESCRIPTION = "Remove max_iterations: 10 limit — iterate until zero violations; the limit existed because old LLM calls were expensive, not because 10 is a meaningful stopping point".freeze
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
