# frozen_string_literal: true
# TODO artifact AB402: FixLoop has two strategies (llm_pass, fast_pass) but the strategy selection logic is in scanner.rb, not FixLoop — SRP vi
module Master
  module Backlog
    module Stubs
      module AB
        class AB402
          ID = "AB402".freeze
          DESCRIPTION = "FixLoop has two strategies (llm_pass, fast_pass) but the strategy selection logic is in scanner.rb, not FixLoop — SRP violation in the scanner itself; move strategy selection to FixLoop".freeze
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
