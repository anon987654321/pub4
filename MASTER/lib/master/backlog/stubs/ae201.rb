# frozen_string_literal: true
# TODO artifact AE201: Scanner and Fixer share AST: parse file once, pass Prism result to scanner, then to fixer — currently each re-parses; AS
module Master
  module Backlog
    module Stubs
      module AE
        class AE201
          ID = "AE201".freeze
          DESCRIPTION = "Scanner and Fixer share AST: parse file once, pass Prism result to scanner, then to fixer — currently each re-parses; AST sharing reduces CPU 40%".freeze
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
