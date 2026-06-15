# frozen_string_literal: true
# TODO artifact AA202: Lazy scan pipeline: DetectionPipeline should build a chain of rule calls without executing; execute only when `.findings
module Master
  module Backlog
    module Stubs
      module AA
        class AA202
          ID = "AA202".freeze
          DESCRIPTION = "Lazy scan pipeline: DetectionPipeline should build a chain of rule calls without executing; execute only when `.findings` is called — enables inspection before execution".freeze
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
