# frozen_string_literal: true
# TODO artifact Z408: Normalize string interpolation: prefer `"#{var}"` over `"" + var.to_s` or `var.to_s` concat
module Master
  module Backlog
    module Stubs
      module Z
        class Z408
          ID = "Z408".freeze
          DESCRIPTION = "Normalize string interpolation: prefer `\"\#{var}\"` over `\"\" + var.to_s` or `var.to_s` concat".freeze
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
