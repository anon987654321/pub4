# frozen_string_literal: true
# TODO artifact R302: Design it twice trigger: when proposing a complex solution (>3 files affected), auto-generate a simpler alternative
module Master
  module Backlog
    module Stubs
      module R
        class R302
          ID = "R302".freeze
          DESCRIPTION = "Design it twice trigger: when proposing a complex solution (>3 files affected), auto-generate a simpler alternative".freeze
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
