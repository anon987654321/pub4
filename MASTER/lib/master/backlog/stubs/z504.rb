# frozen_string_literal: true
# TODO artifact Z504: Normalize tags format: all rule tags as `tags: %i[TAG_ONE TAG_TWO]` — audit for string arrays `tags: ["TAG_ONE"]`
module Master
  module Backlog
    module Stubs
      module Z
        class Z504
          ID = "Z504".freeze
          DESCRIPTION = "Normalize tags format: all rule tags as `tags: %i[TAG_ONE TAG_TWO]` — audit for string arrays `tags: [\"TAG_ONE\"]`".freeze
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
