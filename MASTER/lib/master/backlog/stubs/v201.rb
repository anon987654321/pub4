# frozen_string_literal: true
# TODO artifact V201: `Converge::Rule` → `Converge::ConfigurableRule` — disambiguate from `Judge::Scan::Rule`
module Master
  module Backlog
    module Stubs
      module V
        class V201
          ID = "V201".freeze
          DESCRIPTION = "`Converge::Rule` → `Converge::ConfigurableRule` — disambiguate from `Judge::Scan::Rule`".freeze
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
