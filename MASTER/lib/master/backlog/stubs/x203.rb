# frozen_string_literal: true
# TODO artifact X203: Prism parse-once, reuse: parse Ruby AST once per file and pass to all structural rules — currently each rule re-parses i
module Master
  module Backlog
    module Stubs
      module X
        class X203
          ID = "X203".freeze
          DESCRIPTION = "Prism parse-once, reuse: parse Ruby AST once per file and pass to all structural rules — currently each rule re-parses independently".freeze
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
