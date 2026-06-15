# frozen_string_literal: true
# TODO artifact AD302: Error messages must use active voice identifying who must act: "Move method foo to its own class" not "Method foo violat
module Master
  module Backlog
    module Stubs
      module AD
        class AD302
          ID = "AD302".freeze
          DESCRIPTION = "Error messages must use active voice identifying who must act: \"Move method foo to its own class\" not \"Method foo violates SRP\"".freeze
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
