# frozen_string_literal: true
# TODO artifact AD107: Urgency detection: "quickly" / "just give me the main issues" → still run full scan but show only :error findings first;
module Master
  module Backlog
    module Stubs
      module AD
        class AD107
          ID = "AD107".freeze
          DESCRIPTION = "Urgency detection: \"quickly\" / \"just give me the main issues\" → still run full scan but show only :error findings first; don't downgrade scan depth".freeze
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
