# frozen_string_literal: true
# TODO artifact AD109: Question vs command distinction: "what's wrong with this?" → report; "fix what's wrong with this" → fix; detect question
module Master
  module Backlog
    module Stubs
      module AD
        class AD109
          ID = "AD109".freeze
          DESCRIPTION = "Question vs command distinction: \"what's wrong with this?\" → report; \"fix what's wrong with this\" → fix; detect question mark and interrogative verbs".freeze
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
