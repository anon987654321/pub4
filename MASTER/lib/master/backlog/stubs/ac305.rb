# frozen_string_literal: true
# TODO artifact AC305: Remove --parallel/--no-parallel flags — always parallel on multi-core; --no-parallel was a workaround for Termux fork() 
module Master
  module Backlog
    module Stubs
      module AC
        class AC305
          ID = "AC305".freeze
          DESCRIPTION = "Remove --parallel/--no-parallel flags — always parallel on multi-core; --no-parallel was a workaround for Termux fork() ban; use Thread instead of Process".freeze
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
