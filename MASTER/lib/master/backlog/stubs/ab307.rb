# frozen_string_literal: true
# TODO artifact AB307: CyclomaticComplexityRule description says "max 10" but soul.yml SIMPLEST_WORKS says "max 20 lines" for methods — two dif
module Master
  module Backlog
    module Stubs
      module AB
        class AB307
          ID = "AB307".freeze
          DESCRIPTION = "CyclomaticComplexityRule description says \"max 10\" but soul.yml SIMPLEST_WORKS says \"max 20 lines\" for methods — two different metrics (CC vs length) used interchangeably in violation messages; distinguish them explicitly".freeze
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
