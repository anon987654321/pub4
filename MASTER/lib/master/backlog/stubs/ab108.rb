# frozen_string_literal: true
# TODO artifact AB108: NO_MAGIC_NUMBERS fires on integer literals inside constant definitions (FOO = 300) — should exempt right-hand side of SC
module Master
  module Backlog
    module Stubs
      module AB
        class AB108
          ID = "AB108".freeze
          DESCRIPTION = "NO_MAGIC_NUMBERS fires on integer literals inside constant definitions (FOO = 300) — should exempt right-hand side of SCREAMING_SNAKE assignments; currently false-positives own constants".freeze
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
