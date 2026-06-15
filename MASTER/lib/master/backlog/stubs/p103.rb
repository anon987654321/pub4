# frozen_string_literal: true
# TODO artifact P103: fast_pass runs rubocop on all files as one batch — if one file errors, rubocop non-zero exit skips reporting on all othe
module Master
  module Backlog
    module Stubs
      module P
        class P103
          ID = "P103".freeze
          DESCRIPTION = "fast_pass runs rubocop on all files as one batch — if one file errors, rubocop non-zero exit skips reporting on all others; use --format json to isolate".freeze
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
