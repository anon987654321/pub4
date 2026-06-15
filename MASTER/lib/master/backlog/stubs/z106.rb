# frozen_string_literal: true
# TODO artifact Z106: Normalize file extension guards: all file-type checks use `path.to_s.end_with?(".rb", ".rake")` pattern — audit for `=~`
module Master
  module Backlog
    module Stubs
      module Z
        class Z106
          ID = "Z106".freeze
          DESCRIPTION = "Normalize file extension guards: all file-type checks use `path.to_s.end_with?(\".rb\", \".rake\")` pattern — audit for `=~`, `match?(/\\.rb/)` variants".freeze
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
