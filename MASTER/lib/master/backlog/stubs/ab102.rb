# frozen_string_literal: true
# TODO artifact AB102: CONSECUTIVE_BLANK_LINES (lexical rule) overlaps with C01 AstFixer collapse_blank_lines — same dedup; AstFixer is determi
module Master
  module Backlog
    module Stubs
      module AB
        class AB102
          ID = "AB102".freeze
          DESCRIPTION = "CONSECUTIVE_BLANK_LINES (lexical rule) overlaps with C01 AstFixer collapse_blank_lines — same dedup; AstFixer is deterministic and runs first; lexical rule becomes unreachable".freeze
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
