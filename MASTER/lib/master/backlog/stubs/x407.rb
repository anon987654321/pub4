# frozen_string_literal: true
# TODO artifact X407: Sort findings by severity then line number: currently reported in rule-registry order — reorder before output
module Master
  module Backlog
    module Stubs
      module X
        class X407
          ID = "X407".freeze
          DESCRIPTION = "Sort findings by severity then line number: currently reported in rule-registry order — reorder before output".freeze
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
