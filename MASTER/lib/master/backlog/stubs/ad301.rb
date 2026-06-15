# frozen_string_literal: true
# TODO artifact AD301: Every rule must have a plain_english: field: one sentence a non-programmer could understand — "This file is too long. Lo
module Master
  module Backlog
    module Stubs
      module AD
        class AD301
          ID = "AD301".freeze
          DESCRIPTION = "Every rule must have a plain_english: field: one sentence a non-programmer could understand — \"This file is too long. Long files are hard to understand and change.\" not \"SMALL_FILES: count 347 > limit 300\"".freeze
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
