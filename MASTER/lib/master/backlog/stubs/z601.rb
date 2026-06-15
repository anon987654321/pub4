# frozen_string_literal: true
# TODO artifact Z601: Replace `src.lines.each_with_index.filter_map` with `src.each_line.with_index.filter_map` — avoids creating full lines a
module Master
  module Backlog
    module Stubs
      module Z
        class Z601
          ID = "Z601".freeze
          DESCRIPTION = "Replace `src.lines.each_with_index.filter_map` with `src.each_line.with_index.filter_map` — avoids creating full lines array".freeze
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
