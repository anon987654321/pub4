# frozen_string_literal: true
# TODO artifact AF502: Refusal categories: weapons_technical, malware_creation, csam, self_harm_enabling, criminal_specific — named explicitly,
module Master
  module Backlog
    module Stubs
      module AF
        class AF502
          ID = "AF502".freeze
          DESCRIPTION = "Refusal categories: weapons_technical, malware_creation, csam, self_harm_enabling, criminal_specific — named explicitly, not \"harmful content\"".freeze
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
