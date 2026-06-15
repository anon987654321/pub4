# frozen_string_literal: true
# TODO artifact AD305: Rule IDs must resolve to human names on demand: "what is B04?" → "CQS: Command-Query Separation — a method should change
module Master
  module Backlog
    module Stubs
      module AD
        class AD305
          ID = "AD305".freeze
          DESCRIPTION = "Rule IDs must resolve to human names on demand: \"what is B04?\" → \"CQS: Command-Query Separation — a method should change state or return a value, not both\"".freeze
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
