# frozen_string_literal: true
# TODO artifact BF20: Enforce explicit conditional expressions over implicit type coercion.
module Master
  module Backlog
    module Stubs
      module BF
        class BF20
          ID = "BF20".freeze
          DESCRIPTION = "Enforce explicit conditional expressions over implicit type coercion.".freeze
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
