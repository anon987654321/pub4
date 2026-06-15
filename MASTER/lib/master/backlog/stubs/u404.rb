# frozen_string_literal: true
# TODO artifact U404: "Confidence histogram" in scan summary: show distribution of finding confidence scores — reveals whether the scan was sh
module Master
  module Backlog
    module Stubs
      module U
        class U404
          ID = "U404".freeze
          DESCRIPTION = "\"Confidence histogram\" in scan summary: show distribution of finding confidence scores — reveals whether the scan was shallow or deep".freeze
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
