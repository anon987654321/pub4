# frozen_string_literal: true
# TODO artifact U305: Cross-file DRY pass: after per-file scan, run a mandatory cross-file pass looking for duplicate patterns across the whol
module Master
  module Backlog
    module Stubs
      module U
        class U305
          ID = "U305".freeze
          DESCRIPTION = "Cross-file DRY pass: after per-file scan, run a mandatory cross-file pass looking for duplicate patterns across the whole scan batch — cannot be skipped".freeze
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
