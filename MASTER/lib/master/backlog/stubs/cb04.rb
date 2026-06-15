# frozen_string_literal: true
# TODO artifact CB04: brgen: add anonymous post gate (2 posts before signup) with MASTER moderation (BA7)
module Master
  module Backlog
    module Stubs
      module CB
        class CB04
          ID = "CB04".freeze
          DESCRIPTION = "brgen: add anonymous post gate (2 posts before signup) with MASTER moderation (BA7)".freeze
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
