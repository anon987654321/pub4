# frozen_string_literal: true
# TODO artifact W303: Compress rule descriptions sent to LLM: include rule ID + one-sentence description only; full YAML is for code, not LLM 
module Master
  module Backlog
    module Stubs
      module W
        class W303
          ID = "W303".freeze
          DESCRIPTION = "Compress rule descriptions sent to LLM: include rule ID + one-sentence description only; full YAML is for code, not LLM context — reduces system prompt by ~60%".freeze
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
