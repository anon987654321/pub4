# frozen_string_literal: true
# TODO artifact AA108: Private matcher methods with `_` prefix: all internal rule-matching helpers named `_match_pattern`, `_match_ast`, `_matc
module Master
  module Backlog
    module Stubs
      module AA
        class AA108
          ID = "AA108".freeze
          DESCRIPTION = "Private matcher methods with `_` prefix: all internal rule-matching helpers named `_match_pattern`, `_match_ast`, `_match_cross_file` — public surface is just `check`".freeze
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
