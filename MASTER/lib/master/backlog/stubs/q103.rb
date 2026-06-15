# frozen_string_literal: true
# TODO artifact Q103: No tab completion for filenames after /scan, /fix, /critique
module Master
  module Backlog
    module Stubs
      module Q
        class Q103
          ID = "Q103".freeze
          DESCRIPTION = "No tab completion for filenames after /scan, /fix, /critique".freeze
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
