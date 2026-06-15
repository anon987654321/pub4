# frozen_string_literal: true
# TODO artifact AA406: Shape-friendly instance variable initialization: pre-initialize all Rule instance variables in Rule#initialize to nil/de
module Master
  module Backlog
    module Stubs
      module AA
        class AA406
          ID = "AA406".freeze
          DESCRIPTION = "Shape-friendly instance variable initialization: pre-initialize all Rule instance variables in Rule#initialize to nil/default — YJIT optimizes known shapes".freeze
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
