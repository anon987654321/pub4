# frozen_string_literal: true
# TODO artifact W507: Codify no-new-files policy as scanner: if MASTER proposes creating a new .rb file, it must first check if an existing fi
module Master
  module Backlog
    module Stubs
      module W
        class W507
          ID = "W507".freeze
          DESCRIPTION = "Codify no-new-files policy as scanner: if MASTER proposes creating a new .rb file, it must first check if an existing file's responsibility overlaps — PREMATURE_FILE advisory rule".freeze
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
