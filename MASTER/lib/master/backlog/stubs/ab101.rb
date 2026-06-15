# frozen_string_literal: true
# TODO artifact AB101: TRAILING_WHITESPACE (lexical rule) overlaps with C02 AstFixer strip_trailing_whitespace — two systems fix the same thing
module Master
  module Backlog
    module Stubs
      module AB
        class AB101
          ID = "AB101".freeze
          DESCRIPTION = "TRAILING_WHITESPACE (lexical rule) overlaps with C02 AstFixer strip_trailing_whitespace — two systems fix the same thing; deduplicate to AstFixer only, remove lexical rule".freeze
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
