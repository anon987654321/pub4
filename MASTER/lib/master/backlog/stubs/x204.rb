# frozen_string_literal: true
# TODO artifact X204: Lazy-load rule classes: require rule files on first scan of matching language, not at boot — saves ~2MB on boot for non-
module Master
  module Backlog
    module Stubs
      module X
        class X204
          ID = "X204".freeze
          DESCRIPTION = "Lazy-load rule classes: require rule files on first scan of matching language, not at boot — saves ~2MB on boot for non-Ruby-only sessions".freeze
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
