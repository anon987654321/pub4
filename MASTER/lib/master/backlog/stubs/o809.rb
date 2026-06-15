# frozen_string_literal: true
# TODO artifact O809: FixLoop#collect_files uses Dir.glob without .gitignore awareness — use git ls-files for tracked files only
module Master
  module Backlog
    module Stubs
      module O
        class O809
          ID = "O809".freeze
          DESCRIPTION = "FixLoop#collect_files uses Dir.glob without .gitignore awareness — use git ls-files for tracked files only".freeze
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
