# frozen_string_literal: true
# TODO artifact AM1202: Self-reminder (Xie et al. 2023): append reminders of system instructions at both beginning and end of every prompt — sim
module Master
  module Backlog
    module Stubs
      module AM
        class AM1202
          ID = "AM1202".freeze
          DESCRIPTION = "Self-reminder (Xie et al. 2023): append reminders of system instructions at both beginning and end of every prompt — simple but effective jailbreak resistance".freeze
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
