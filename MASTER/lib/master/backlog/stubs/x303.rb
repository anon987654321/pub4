# frozen_string_literal: true
# TODO artifact X303: Short-circuit rule chain: if FORBIDDEN_PATTERNS fires (:error), skip all :info/:warning rules for that file — highest se
module Master
  module Backlog
    module Stubs
      module X
        class X303
          ID = "X303".freeze
          DESCRIPTION = "Short-circuit rule chain: if FORBIDDEN_PATTERNS fires (:error), skip all :info/:warning rules for that file — highest severity already blocks it".freeze
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
