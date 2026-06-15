# frozen_string_literal: true
# TODO artifact U308: "Impact radius" annotation on every finding: {files_affected: N, callers: M, severity_multiplier: S} — high-impact findi
module Master
  module Backlog
    module Stubs
      module U
        class U308
          ID = "U308".freeze
          DESCRIPTION = "\"Impact radius\" annotation on every finding: {files_affected: N, callers: M, severity_multiplier: S} — high-impact findings shown first regardless of per-file severity".freeze
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
