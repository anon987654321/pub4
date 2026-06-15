# frozen_string_literal: true
# TODO artifact R410: Add proposal type: "opportunity" (additive) vs "violation" (corrective) — show separately in UI
module Master
  module Backlog
    module Stubs
      module R
        class R410
          ID = "R410".freeze
          DESCRIPTION = "Add proposal type: \"opportunity\" (additive) vs \"violation\" (corrective) — show separately in UI".freeze
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
