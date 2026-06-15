# frozen_string_literal: true
# TODO artifact S405: Default profile in rules.yml / soul.yml selectable at boot time, overridable per scan invocation
module Master
  module Backlog
    module Stubs
      module S
        class S405
          ID = "S405".freeze
          DESCRIPTION = "Default profile in rules.yml / soul.yml selectable at boot time, overridable per scan invocation".freeze
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
