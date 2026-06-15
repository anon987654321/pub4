# frozen_string_literal: true
# TODO artifact Z103: Normalize finding construction: all rules use `finding(line:, message:)` keyword form — audit for positional calls
module Master
  module Backlog
    module Stubs
      module Z
        class Z103
          ID = "Z103".freeze
          DESCRIPTION = "Normalize finding construction: all rules use `finding(line:, message:)` keyword form — audit for positional calls".freeze
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
