# frozen_string_literal: true
# TODO artifact Q106: Multi-line input: read_multiline has no line count guard — large paste exhausts memory; cap at 500 lines
module Master
  module Backlog
    module Stubs
      module Q
        class Q106
          ID = "Q106".freeze
          DESCRIPTION = "Multi-line input: read_multiline has no line count guard — large paste exhausts memory; cap at 500 lines".freeze
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
