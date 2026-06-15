# frozen_string_literal: true
# TODO artifact O408: /axioms scans lib/; /scan with no arg also scans lib/ — two commands with the same default target, different output form
module Master
  module Backlog
    module Stubs
      module O
        class O408
          ID = "O408".freeze
          DESCRIPTION = "/axioms scans lib/; /scan with no arg also scans lib/ — two commands with the same default target, different output format".freeze
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
