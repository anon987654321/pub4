# frozen_string_literal: true
# TODO artifact AA404: Double-freeze collections: freeze array AND its string elements: `TAGS = %i[SOLID SRP].freeze` (symbols already immutabl
module Master
  module Backlog
    module Stubs
      module AA
        class AA404
          ID = "AA404".freeze
          DESCRIPTION = "Double-freeze collections: freeze array AND its string elements: `TAGS = %i[SOLID SRP].freeze` (symbols already immutable; string arrays need `map!(&:freeze).freeze`)".freeze
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
