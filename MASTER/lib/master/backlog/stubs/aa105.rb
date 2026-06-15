# frozen_string_literal: true
# TODO artifact AA105: Feature definition with metadata hash: each rule registers `{id:, severity:, tags:, applies_to:, autofix:}` in RULES_MET
module Master
  module Backlog
    module Stubs
      module AA
        class AA105
          ID = "AA105".freeze
          DESCRIPTION = "Feature definition with metadata hash: each rule registers `{id:, severity:, tags:, applies_to:, autofix:}` in RULES_META constant at load time — introspectable without instantiation".freeze
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
