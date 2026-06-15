# frozen_string_literal: true
# TODO artifact AA203: Enumerable integration on ScanResult: include Enumerable on the findings collection; implement `each` — enables `.select
module Master
  module Backlog
    module Stubs
      module AA
        class AA203
          ID = "AA203".freeze
          DESCRIPTION = "Enumerable integration on ScanResult: include Enumerable on the findings collection; implement `each` — enables `.select`, `.min_by`, `.group_by` without custom methods".freeze
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
