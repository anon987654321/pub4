# frozen_string_literal: true
# TODO artifact AF301: Tool-search-first principle: before claiming a capability is unavailable, always check tool registry — never say "I can'
module Master
  module Backlog
    module Stubs
      module AF
        class AF301
          ID = "AF301".freeze
          DESCRIPTION = "Tool-search-first principle: before claiming a capability is unavailable, always check tool registry — never say \"I can't do X\" without checking tools".freeze
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
