# frozen_string_literal: true
# TODO artifact Q306: /dry-run missing — run /fix without applying changes, show what would change
module Master
  module Backlog
    module Stubs
      module Q
        class Q306
          ID = "Q306".freeze
          DESCRIPTION = "/dry-run missing — run /fix without applying changes, show what would change".freeze
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
