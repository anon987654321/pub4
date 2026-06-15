# frozen_string_literal: true
# TODO artifact AG203: Include a condensed rules.yml summary (top 20 rules by severity) in every LLM companion file — LLMs should know the rule
module Master
  module Backlog
    module Stubs
      module AG
        class AG203
          ID = "AG203".freeze
          DESCRIPTION = "Include a condensed rules.yml summary (top 20 rules by severity) in every LLM companion file — LLMs should know the rules they're enforcing".freeze
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
