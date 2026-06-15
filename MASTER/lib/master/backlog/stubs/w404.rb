# frozen_string_literal: true
# TODO artifact W404: Codify "never pkg_add base tools": scanner flags `pkg_add relayd`, `pkg_add httpd`, `pkg_add pf` as INSTALL_BASE_TOOL er
module Master
  module Backlog
    module Stubs
      module W
        class W404
          ID = "W404".freeze
          DESCRIPTION = "Codify \"never pkg_add base tools\": scanner flags `pkg_add relayd`, `pkg_add httpd`, `pkg_add pf` as INSTALL_BASE_TOOL error".freeze
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
