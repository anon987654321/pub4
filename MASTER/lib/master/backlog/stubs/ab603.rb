# frozen_string_literal: true
# TODO artifact AB603: /checkpoint creates a snapshot but /snapshot also exists — two commands with same semantic intent; merge to /checkpoint,
module Master
  module Backlog
    module Stubs
      module AB
        class AB603
          ID = "AB603".freeze
          DESCRIPTION = "/checkpoint creates a snapshot but /snapshot also exists — two commands with same semantic intent; merge to /checkpoint, remove /snapshot alias".freeze
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
