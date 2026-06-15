# frozen_string_literal: true
# TODO artifact AD303: Findings must answer "so what?": every message ends with the consequence — "extract helpers — long methods hide bugs and
module Master
  module Backlog
    module Stubs
      module AD
        class AD303
          ID = "AD303".freeze
          DESCRIPTION = "Findings must answer \"so what?\": every message ends with the consequence — \"extract helpers — long methods hide bugs and resist testing\"".freeze
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
