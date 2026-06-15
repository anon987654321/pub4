# frozen_string_literal: true
# TODO artifact P106: scan_dir sorts paths before scanning — sorting is unnecessary overhead on large trees; remove or lazy-sort for display o
module Master
  module Backlog
    module Stubs
      module P
        class P106
          ID = "P106".freeze
          DESCRIPTION = "scan_dir sorts paths before scanning — sorting is unnecessary overhead on large trees; remove or lazy-sort for display only".freeze
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
