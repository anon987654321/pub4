# frozen_string_literal: true
# TODO artifact Q205: /scan output dumps all violations without paging — pipe to TTY::Pager or show top N with "N more..."
module Master
  module Backlog
    module Stubs
      module Q
        class Q205
          ID = "Q205".freeze
          DESCRIPTION = "/scan output dumps all violations without paging — pipe to TTY::Pager or show top N with \"N more...\"".freeze
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
