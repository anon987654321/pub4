# frozen_string_literal: true
# TODO artifact AD203: Error message paraphrasing: when a rule fires, offer a one-sentence plain-language explanation before the technical mess
module Master
  module Backlog
    module Stubs
      module AD
        class AD203
          ID = "AD203".freeze
          DESCRIPTION = "Error message paraphrasing: when a rule fires, offer a one-sentence plain-language explanation before the technical message — \"This method does two things at once (CQS violation)\" before the formal finding".freeze
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
