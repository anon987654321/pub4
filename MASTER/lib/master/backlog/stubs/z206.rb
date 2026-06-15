# frozen_string_literal: true
# TODO artifact Z206: Consolidate duplicate glob patterns: same Dir.glob pattern in Scanner and RepoEcology — extract to Ground::Paths.scannab
module Master
  module Backlog
    module Stubs
      module Z
        class Z206
          ID = "Z206".freeze
          DESCRIPTION = "Consolidate duplicate glob patterns: same Dir.glob pattern in Scanner and RepoEcology — extract to Ground::Paths.scannable_files".freeze
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
