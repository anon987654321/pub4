# frozen_string_literal: true
# TODO artifact S505: Conflict resolution strategy in soul.yml: highest_priority_wins, prompt_user: false — make this configurable
module Master
  module Backlog
    module Stubs
      module S
        class S505
          ID = "S505".freeze
          DESCRIPTION = "Conflict resolution strategy in soul.yml: highest_priority_wins, prompt_user: false — make this configurable".freeze
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
