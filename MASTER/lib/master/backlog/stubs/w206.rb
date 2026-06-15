# frozen_string_literal: true
# TODO artifact W206: Codify DEEP_SCAN_ONLY (already in soul.yml) as a hard scanner gate: if scan_depth != :deep, raise ConfigError — never si
module Master
  module Backlog
    module Stubs
      module W
        class W206
          ID = "W206".freeze
          DESCRIPTION = "Codify DEEP_SCAN_ONLY (already in soul.yml) as a hard scanner gate: if scan_depth != :deep, raise ConfigError — never silently downgrade".freeze
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
