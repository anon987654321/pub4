# frozen_string_literal: true
# TODO artifact W202: Codify "read whole file, not grep snippets": scanner must load full file content before any rule runs — no streaming par
module Master
  module Backlog
    module Stubs
      module W
        class W202
          ID = "W202".freeze
          DESCRIPTION = "Codify \"read whole file, not grep snippets\": scanner must load full file content before any rule runs — no streaming partial-reads that miss context; enforce in scanner.rb#load_file".freeze
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
