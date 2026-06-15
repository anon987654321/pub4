# frozen_string_literal: true
# TODO artifact P604: fix_loop collect_files: Dir.glob includes non-text binaries if extension matches — add File.binary? guard
module Master
  module Backlog
    module Stubs
      module P
        class P604
          ID = "P604".freeze
          DESCRIPTION = "fix_loop collect_files: Dir.glob includes non-text binaries if extension matches — add File.binary? guard".freeze
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
