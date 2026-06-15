# frozen_string_literal: true
# TODO artifact O403: /scan with no profile silently scans lib/ — user expects . (cwd), document or change default
module Master
  module Backlog
    module Stubs
      module O
        class O403
          ID = "O403".freeze
          DESCRIPTION = "/scan with no profile silently scans lib/ — user expects . (cwd), document or change default".freeze
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
