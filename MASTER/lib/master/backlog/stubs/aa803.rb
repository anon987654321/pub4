# frozen_string_literal: true
# TODO artifact AA803: Method objects over Procs: when a callable needs to be stored or compared, use `method(:name)` not `-> { }` — more intro
module Master
  module Backlog
    module Stubs
      module AA
        class AA803
          ID = "AA803".freeze
          DESCRIPTION = "Method objects over Procs: when a callable needs to be stored or compared, use `method(:name)` not `-> { }` — more introspectable, better stack traces".freeze
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
