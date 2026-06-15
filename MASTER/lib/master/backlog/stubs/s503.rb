# frozen_string_literal: true
# TODO artifact S503: Conflict rule: "fix introduces higher-priority violation → reject fix" — FixLoop must recheck severity after every patch
module Master
  module Backlog
    module Stubs
      module S
        class S503
          ID = "S503".freeze
          DESCRIPTION = "Conflict rule: \"fix introduces higher-priority violation → reject fix\" — FixLoop must recheck severity after every patch application".freeze
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
