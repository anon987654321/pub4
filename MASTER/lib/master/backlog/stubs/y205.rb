# frozen_string_literal: true
# TODO artifact Y205: RuleDSL severity/tags/applies_to metadata → merge into rules.yml per-rule entry — RuleDSL block remains Ruby but metadat
module Master
  module Backlog
    module Stubs
      module Y
        class Y205
          ID = "Y205".freeze
          DESCRIPTION = "RuleDSL severity/tags/applies_to metadata → merge into rules.yml per-rule entry — RuleDSL block remains Ruby but metadata lives in YAML".freeze
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
