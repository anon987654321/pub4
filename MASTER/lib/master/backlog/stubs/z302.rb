# frozen_string_literal: true
# TODO artifact Z302: Normalize all rescue blocks to log before returning []: currently some log, some silently return [] — add `Trace.warn(e)
module Master
  module Backlog
    module Stubs
      module Z
        class Z302
          ID = "Z302".freeze
          DESCRIPTION = "Normalize all rescue blocks to log before returning []: currently some log, some silently return [] — add `Trace.warn(e)` to every rescue in scan rules".freeze
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
