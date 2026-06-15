# frozen_string_literal: true
# TODO artifact AB406: /fix and /scan --fix are both valid entry points for the same fix pipeline — duplicate invocation paths with potentially
module Master
  module Backlog
    module Stubs
      module AB
        class AB406
          ID = "AB406".freeze
          DESCRIPTION = "/fix and /scan --fix are both valid entry points for the same fix pipeline — duplicate invocation paths with potentially different defaults; canonicalize one".freeze
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
