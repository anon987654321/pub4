# frozen_string_literal: true
# TODO artifact AC108: Retire /snapshot as alias: /checkpoint is the canonical command; /snapshot is duplicate surface
module Master
  module Backlog
    module Stubs
      module AC
        class AC108
          ID = "AC108".freeze
          DESCRIPTION = "Retire /snapshot as alias: /checkpoint is the canonical command; /snapshot is duplicate surface".freeze
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
