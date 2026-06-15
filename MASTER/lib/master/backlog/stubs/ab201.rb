# frozen_string_literal: true
# TODO artifact AB201: FORBIDDEN_PATTERNS is :error but RACE_CONDITIONS is also :error — yet RACE_CONDITIONS has a much higher false-positive r
module Master
  module Backlog
    module Stubs
      module AB
        class AB201
          ID = "AB201".freeze
          DESCRIPTION = "FORBIDDEN_PATTERNS is :error but RACE_CONDITIONS is also :error — yet RACE_CONDITIONS has a much higher false-positive rate (check-then-set without synchronize fires on valid patterns) — downgrade to :warning or add suppressibility".freeze
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
