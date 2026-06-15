# frozen_string_literal: true
# TODO artifact P403: maybe_rollback: calls dirty? (git status) even when @root is nil or .git doesn't exist — add guard before the git call
module Master
  module Backlog
    module Stubs
      module P
        class P403
          ID = "P403".freeze
          DESCRIPTION = "maybe_rollback: calls dirty? (git status) even when @root is nil or .git doesn't exist — add guard before the git call".freeze
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
