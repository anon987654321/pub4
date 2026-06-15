# frozen_string_literal: true
# TODO artifact AC308: Remove ask_language config — always auto-detect; asking the user was a workaround for ambiguous extensions
module Master
  module Backlog
    module Stubs
      module AC
        class AC308
          ID = "AC308".freeze
          DESCRIPTION = "Remove ask_language config — always auto-detect; asking the user was a workaround for ambiguous extensions".freeze
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
