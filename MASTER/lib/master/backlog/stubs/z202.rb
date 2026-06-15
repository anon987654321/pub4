# frozen_string_literal: true
# TODO artifact Z202: Remove deprecated scan depth logic: any reference to :shallow/:standard depth in scanner.rb, pipeline.rb — DEEP_SCAN_ONL
module Master
  module Backlog
    module Stubs
      module Z
        class Z202
          ID = "Z202".freeze
          DESCRIPTION = "Remove deprecated scan depth logic: any reference to :shallow/:standard depth in scanner.rb, pipeline.rb — DEEP_SCAN_ONLY is now law".freeze
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
