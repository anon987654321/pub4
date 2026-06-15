# frozen_string_literal: true
# TODO artifact CV08: MASTER: add `--council` flag to CLI scan — run deliberation even on small files
module Master
  module Backlog
    module Stubs
      module CV
        class CV08
          ID = "CV08".freeze
          DESCRIPTION = "MASTER: add `--council` flag to CLI scan — run deliberation even on small files".freeze
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
