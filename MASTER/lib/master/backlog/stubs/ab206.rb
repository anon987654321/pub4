# frozen_string_literal: true
# TODO artifact AB206: FileLayoutRule (B05) fires as :info — frozen_string_literal missing is already :warning in FROZEN_LITERAL; two rules for
module Master
  module Backlog
    module Stubs
      module AB
        class AB206
          ID = "AB206".freeze
          DESCRIPTION = "FileLayoutRule (B05) fires as :info — frozen_string_literal missing is already :warning in FROZEN_LITERAL; two rules for the same finding create duplicate findings at different severities".freeze
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
