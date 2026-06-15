# frozen_string_literal: true
# TODO artifact AM202: Reflexion (Shinn et al. 2023): after failed fix, generate verbal self-critique ("I tried X but it failed because Y") and
module Master
  module Backlog
    module Stubs
      module AM
        class AM202
          ID = "AM202".freeze
          DESCRIPTION = "Reflexion (Shinn et al. 2023): after failed fix, generate verbal self-critique (\"I tried X but it failed because Y\") and inject as context for next attempt — implement in `Loop::Reflexion`".freeze
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
