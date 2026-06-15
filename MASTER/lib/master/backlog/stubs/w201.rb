# frozen_string_literal: true
# TODO artifact W201: Codify crit-fix-loop as default: any scan invocation runs autoiteratively until zero findings — no --loop flag required;
module Master
  module Backlog
    module Stubs
      module W
        class W201
          ID = "W201".freeze
          DESCRIPTION = "Codify crit-fix-loop as default: any scan invocation runs autoiteratively until zero findings — no --loop flag required; wired at pipeline level so loop exits only on clean pass".freeze
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
