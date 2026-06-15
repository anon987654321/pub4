# frozen_string_literal: true
# TODO artifact AA102: Plugin validation at load time: when a rule file is required, immediately validate it has `check` method and `@id` set —
module Master
  module Backlog
    module Stubs
      module AA
        class AA102
          ID = "AA102".freeze
          DESCRIPTION = "Plugin validation at load time: when a rule file is required, immediately validate it has `check` method and `@id` set — fail loudly at boot, not at scan time".freeze
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
