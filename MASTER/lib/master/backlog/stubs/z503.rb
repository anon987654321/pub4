# frozen_string_literal: true
# TODO artifact Z503: Remove default: true from rules that can't be disabled — if a rule always runs, `default: true` is noise
module Master
  module Backlog
    module Stubs
      module Z
        class Z503
          ID = "Z503".freeze
          DESCRIPTION = "Remove default: true from rules that can't be disabled — if a rule always runs, `default: true` is noise".freeze
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
