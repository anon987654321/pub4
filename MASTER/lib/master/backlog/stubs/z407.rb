# frozen_string_literal: true
# TODO artifact Z407: Replace `&.` safe navigation with explicit guard clause where the nil case has meaningful behavior — don't hide nil sema
module Master
  module Backlog
    module Stubs
      module Z
        class Z407
          ID = "Z407".freeze
          DESCRIPTION = "Replace `&.` safe navigation with explicit guard clause where the nil case has meaningful behavior — don't hide nil semantics".freeze
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
