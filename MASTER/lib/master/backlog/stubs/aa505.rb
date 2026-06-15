# frozen_string_literal: true
# TODO artifact AA505: Model pledge/unveil as MASTER rules: any Ruby script lacking `Process.pledge` on OpenBSD gets MISSING_PLEDGE advisory fi
module Master
  module Backlog
    module Stubs
      module AA
        class AA505
          ID = "AA505".freeze
          DESCRIPTION = "Model pledge/unveil as MASTER rules: any Ruby script lacking `Process.pledge` on OpenBSD gets MISSING_PLEDGE advisory finding".freeze
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
