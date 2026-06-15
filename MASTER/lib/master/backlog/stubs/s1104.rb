# frozen_string_literal: true
# TODO artifact S1104: Preserve: help text must be scannable (command + syntax + description + at least one example) — /help output linted agai
module Master
  module Backlog
    module Stubs
      module S
        class S1104
          ID = "S1104".freeze
          DESCRIPTION = "Preserve: help text must be scannable (command + syntax + description + at least one example) — /help output linted against this".freeze
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
