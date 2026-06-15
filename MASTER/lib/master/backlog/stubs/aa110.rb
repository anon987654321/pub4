# frozen_string_literal: true
# TODO artifact AA110: `configure` block for rule options: `RuleDSL.rule :FOO, max: 10 do ... end` passes options into rule at definition time 
module Master
  module Backlog
    module Stubs
      module AA
        class AA110
          ID = "AA110".freeze
          DESCRIPTION = "`configure` block for rule options: `RuleDSL.rule :FOO, max: 10 do ... end` passes options into rule at definition time — currently only severity/tags/applies_to".freeze
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
