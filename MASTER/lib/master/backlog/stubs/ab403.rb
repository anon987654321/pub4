# frozen_string_literal: true
# TODO artifact AB403: DetectionPipeline has a cyclomatic_complexity method that's being superseded by CyclomaticComplexityRule (B08) — old CC 
module Master
  module Backlog
    module Stubs
      module AB
        class AB403
          ID = "AB403".freeze
          DESCRIPTION = "DetectionPipeline has a cyclomatic_complexity method that's being superseded by CyclomaticComplexityRule (B08) — old CC logic still runs in parallel; will produce duplicate findings until removed".freeze
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
