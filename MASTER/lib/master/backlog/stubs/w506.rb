# frozen_string_literal: true
# TODO artifact W506: Codify single-SSH-connection discipline: any shell-out in MASTER that opens a second SSH connection without ControlMaste
module Master
  module Backlog
    module Stubs
      module W
        class W506
          ID = "W506".freeze
          DESCRIPTION = "Codify single-SSH-connection discipline: any shell-out in MASTER that opens a second SSH connection without ControlMaster fires PARALLEL_SSH warning".freeze
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
