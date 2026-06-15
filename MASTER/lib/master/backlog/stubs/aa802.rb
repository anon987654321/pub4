# frozen_string_literal: true
# TODO artifact AA802: Enumerable everywhere: any class that manages a collection should include Enumerable and implement `each` — Rule.registr
module Master
  module Backlog
    module Stubs
      module AA
        class AA802
          ID = "AA802".freeze
          DESCRIPTION = "Enumerable everywhere: any class that manages a collection should include Enumerable and implement `each` — Rule.registry, ScanResult, FindingCollection".freeze
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
