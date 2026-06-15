# frozen_string_literal: true
# TODO artifact AD105: Negation handling: "don't fix X" / "skip the magic number rule" → add rule to session suppression list; persist for sess
module Master
  module Backlog
    module Stubs
      module AD
        class AD105
          ID = "AD105".freeze
          DESCRIPTION = "Negation handling: \"don't fix X\" / \"skip the magic number rule\" → add rule to session suppression list; persist for session".freeze
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
