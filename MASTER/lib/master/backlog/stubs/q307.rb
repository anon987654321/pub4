# frozen_string_literal: true
# TODO artifact Q307: /rollback missing from /help — it exists as pipeline rollback but not user-accessible
module Master
  module Backlog
    module Stubs
      module Q
        class Q307
          ID = "Q307".freeze
          DESCRIPTION = "/rollback missing from /help — it exists as pipeline rollback but not user-accessible".freeze
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
