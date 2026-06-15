# frozen_string_literal: true
# TODO artifact AD304: Severity labels must be translated: :error → "must fix before shipping", :warning → "fix soon", :info → "consider when r
module Master
  module Backlog
    module Stubs
      module AD
        class AD304
          ID = "AD304".freeze
          DESCRIPTION = "Severity labels must be translated: :error → \"must fix before shipping\", :warning → \"fix soon\", :info → \"consider when refactoring\"".freeze
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
