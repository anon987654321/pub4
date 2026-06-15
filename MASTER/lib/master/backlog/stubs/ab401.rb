# frozen_string_literal: true
# TODO artifact AB401: AstFixer runs before scan but AstFixer's normalise_null_comparison skips /judge/scan/ files — scanner files can contain 
module Master
  module Backlog
    module Stubs
      module AB
        class AB401
          ID = "AB401".freeze
          DESCRIPTION = "AstFixer runs before scan but AstFixer's normalise_null_comparison skips /judge/scan/ files — scanner files can contain SQL patterns but are exempt; undocumented exclusion; add comment explaining why".freeze
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
