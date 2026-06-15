# frozen_string_literal: true
# TODO artifact T1001: Linting before commit: run rubocop (dry-run) on every changed file before creating git commit — block commit on :error f
module Master
  module Backlog
    module Stubs
      module T
        class T1001
          ID = "T1001".freeze
          DESCRIPTION = "Linting before commit: run rubocop (dry-run) on every changed file before creating git commit — block commit on :error findings".freeze
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
