# frozen_string_literal: true
# TODO artifact W503: Codify outsource-to-gems principle: if a well-maintained gem exists (flay, reek, rubocop), prefer it over reinvention — 
module Master
  module Backlog
    module Stubs
      module W
        class W503
          ID = "W503".freeze
          DESCRIPTION = "Codify outsource-to-gems principle: if a well-maintained gem exists (flay, reek, rubocop), prefer it over reinvention — add as REINVENTED_WHEEL advisory rule".freeze
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
