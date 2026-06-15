# frozen_string_literal: true
# TODO artifact AB505: data/patterns.yml and data/rules.yml both contain regex patterns for the same smells — DRY violation in the data layer; 
module Master
  module Backlog
    module Stubs
      module AB
        class AB505
          ID = "AB505".freeze
          DESCRIPTION = "data/patterns.yml and data/rules.yml both contain regex patterns for the same smells — DRY violation in the data layer; rules.yml patterns should be the single source".freeze
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
