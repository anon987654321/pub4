# frozen_string_literal: true
# TODO artifact AB503: data/standing_orders.yml and data/workflow.yml both define execution limits — max_iterations appears in both with potent
module Master
  module Backlog
    module Stubs
      module AB
        class AB503
          ID = "AB503".freeze
          DESCRIPTION = "data/standing_orders.yml and data/workflow.yml both define execution limits — max_iterations appears in both with potentially different values; single source of truth required".freeze
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
