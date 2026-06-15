# frozen_string_literal: true
# TODO artifact W502: Codify no-regex-when-string-suffices: if pattern is a literal string with no metacharacters, flag as USE_STRING_MATCH in
module Master
  module Backlog
    module Stubs
      module W
        class W502
          ID = "W502".freeze
          DESCRIPTION = "Codify no-regex-when-string-suffices: if pattern is a literal string with no metacharacters, flag as USE_STRING_MATCH instead of /regex/ — add as UNNECESSARY_REGEX lexical rule".freeze
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
