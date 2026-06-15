# frozen_string_literal: true
# TODO artifact AB204: DATA_CLASS fires as :info but should be :warning — a data-only class with no behavior is a design smell, not a style pre
module Master
  module Backlog
    module Stubs
      module AB
        class AB204
          ID = "AB204".freeze
          DESCRIPTION = "DATA_CLASS fires as :info but should be :warning — a data-only class with no behavior is a design smell, not a style preference".freeze
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
