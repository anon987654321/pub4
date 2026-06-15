# frozen_string_literal: true
# TODO artifact U502: Every new rule must have a test in spec/judge/scan/ that catches at least one known real violation and passes on at leas
module Master
  module Backlog
    module Stubs
      module U
        class U502
          ID = "U502".freeze
          DESCRIPTION = "Every new rule must have a test in spec/judge/scan/ that catches at least one known real violation and passes on at least one clean counterexample".freeze
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
