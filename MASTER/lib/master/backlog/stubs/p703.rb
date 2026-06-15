# frozen_string_literal: true
# TODO artifact P703: SemanticRule runs on every file even when lexical rules already caught the violation — skip semantic if file has unresol
module Master
  module Backlog
    module Stubs
      module P
        class P703
          ID = "P703".freeze
          DESCRIPTION = "SemanticRule runs on every file even when lexical rules already caught the violation — skip semantic if file has unresolved lexical errors first".freeze
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
