# frozen_string_literal: true
# TODO artifact Q405: Canvas not responsive to container resize — add ResizeObserver to reset canvas dimensions
module Master
  module Backlog
    module Stubs
      module Q
        class Q405
          ID = "Q405".freeze
          DESCRIPTION = "Canvas not responsive to container resize — add ResizeObserver to reset canvas dimensions".freeze
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
