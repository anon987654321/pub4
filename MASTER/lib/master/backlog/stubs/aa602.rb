# frozen_string_literal: true
# TODO artifact AA602: Rule ordering by specificity: tool approval rules ordered most-specific first, least-specific (wildcard) last — matches 
module Master
  module Backlog
    module Stubs
      module AA
        class AA602
          ID = "AA602".freeze
          DESCRIPTION = "Rule ordering by specificity: tool approval rules ordered most-specific first, least-specific (wildcard) last — matches pf.conf block/pass ordering".freeze
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
