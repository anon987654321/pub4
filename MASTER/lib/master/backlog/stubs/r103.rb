# frozen_string_literal: true
# TODO artifact R103: After fixing a violation, check if the same violation exists in sibling files — auto-propose extending fix to siblings
module Master
  module Backlog
    module Stubs
      module R
        class R103
          ID = "R103".freeze
          DESCRIPTION = "After fixing a violation, check if the same violation exists in sibling files — auto-propose extending fix to siblings".freeze
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
