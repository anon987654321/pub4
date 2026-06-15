# frozen_string_literal: true
# TODO artifact S1202: Cross-file DRY: detect duplicate_glob_patterns (same Dir.glob pattern across 3+ files → extract Core.glob_files)
module Master
  module Backlog
    module Stubs
      module S
        class S1202
          ID = "S1202".freeze
          DESCRIPTION = "Cross-file DRY: detect duplicate_glob_patterns (same Dir.glob pattern across 3+ files → extract Core.glob_files)".freeze
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
