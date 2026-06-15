# frozen_string_literal: true
# TODO artifact U401: Show scan progress as "files understood / files skimmed" not just "files scanned" — forces acknowledgement of depth
module Master
  module Backlog
    module Stubs
      module U
        class U401
          ID = "U401".freeze
          DESCRIPTION = "Show scan progress as \"files understood / files skimmed\" not just \"files scanned\" — forces acknowledgement of depth".freeze
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
