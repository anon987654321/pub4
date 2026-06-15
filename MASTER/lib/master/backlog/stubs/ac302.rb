# frozen_string_literal: true
# TODO artifact AC302: Remove --dry-run from all commands — preview is always shown before destructive operations; no flag needed
module Master
  module Backlog
    module Stubs
      module AC
        class AC302
          ID = "AC302".freeze
          DESCRIPTION = "Remove --dry-run from all commands — preview is always shown before destructive operations; no flag needed".freeze
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
