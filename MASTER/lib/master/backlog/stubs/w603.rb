# frozen_string_literal: true
# TODO artifact W603: PROXIMITY rule: Ruby = tests next to implementation; YAML = config adjacent to the behavior it controls; Prose = evidenc
module Master
  module Backlog
    module Stubs
      module W
        class W603
          ID = "W603".freeze
          DESCRIPTION = "PROXIMITY rule: Ruby = tests next to implementation; YAML = config adjacent to the behavior it controls; Prose = evidence near the claim; CSS = selector near the element it styles".freeze
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
