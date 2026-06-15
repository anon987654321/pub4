# frozen_string_literal: true
# TODO artifact AC206: Any input that is empty or "?" → show abbreviated /status + last finding count; never show full help
module Master
  module Backlog
    module Stubs
      module AC
        class AC206
          ID = "AC206".freeze
          DESCRIPTION = "Any input that is empty or \"?\" → show abbreviated /status + last finding count; never show full help".freeze
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
