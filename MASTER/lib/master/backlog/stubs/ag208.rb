# frozen_string_literal: true
# TODO artifact AG208: Include MASTER's OpenBSD rules: relayd not nginx, doas not sudo, pledge/unveil for new daemons, base tools not pkg_add'd
module Master
  module Backlog
    module Stubs
      module AG
        class AG208
          ID = "AG208".freeze
          DESCRIPTION = "Include MASTER's OpenBSD rules: relayd not nginx, doas not sudo, pledge/unveil for new daemons, base tools not pkg_add'd".freeze
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
