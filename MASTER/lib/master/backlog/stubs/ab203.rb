# frozen_string_literal: true
# TODO artifact AB203: SMALL_FILES and SmallFilesRule both have :warning severity — consistent, but files >500 lines should escalate to :error;
module Master
  module Backlog
    module Stubs
      module AB
        class AB203
          ID = "AB203".freeze
          DESCRIPTION = "SMALL_FILES and SmallFilesRule both have :warning severity — consistent, but files >500 lines should escalate to :error; add tiered severity".freeze
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
