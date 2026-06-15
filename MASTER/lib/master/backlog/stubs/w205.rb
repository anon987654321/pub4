# frozen_string_literal: true
# TODO artifact W205: Codify "second-pass obligation" as named pass in ScanPipeline: after finding collection, re-run with findings in context
module Master
  module Backlog
    module Stubs
      module W
        class W205
          ID = "W205".freeze
          DESCRIPTION = "Codify \"second-pass obligation\" as named pass in ScanPipeline: after finding collection, re-run with findings in context asking \"what did I miss?\" — not optional".freeze
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
