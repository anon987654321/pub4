# frozen_string_literal: true
# TODO artifact AB304: COMMENTS_AS_DEODORANT fires on "This method returns…" — should exempt method documentation at class/module boundary (fir
module Master
  module Backlog
    module Stubs
      module AB
        class AB304
          ID = "AB304".freeze
          DESCRIPTION = "COMMENTS_AS_DEODORANT fires on \"This method returns…\" — should exempt method documentation at class/module boundary (first comment after a class/module declaration)".freeze
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
