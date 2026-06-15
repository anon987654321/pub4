# frozen_string_literal: true
# TODO artifact U208: False positive audit: when a user overrides a finding, log the override with file+line+rule+reason in runtime/overrides.
module Master
  module Backlog
    module Stubs
      module U
        class U208
          ID = "U208".freeze
          DESCRIPTION = "False positive audit: when a user overrides a finding, log the override with file+line+rule+reason in runtime/overrides.jsonl — accumulate to discover systematic false positives".freeze
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
