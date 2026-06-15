# frozen_string_literal: true
# TODO artifact O401: /fix loop starts background; /fix <path> runs synchronously — same command, opposite semantics — split /fix and /watch
module Master
  module Backlog
    module Stubs
      module O
        class O401
          ID = "O401".freeze
          DESCRIPTION = "/fix loop starts background; /fix <path> runs synchronously — same command, opposite semantics — split /fix and /watch".freeze
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
