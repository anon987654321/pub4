# frozen_string_literal: true
# TODO artifact AB103: FROZEN_LITERAL (lexical rule) overlaps with C00 AstFixer add_frozen_header — rule fires on a file that AstFixer will imm
module Master
  module Backlog
    module Stubs
      module AB
        class AB103
          ID = "AB103".freeze
          DESCRIPTION = "FROZEN_LITERAL (lexical rule) overlaps with C00 AstFixer add_frozen_header — rule fires on a file that AstFixer will immediately fix; report only if autofix is disabled".freeze
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
