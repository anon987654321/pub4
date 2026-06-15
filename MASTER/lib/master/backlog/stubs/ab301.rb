# frozen_string_literal: true
# TODO artifact AB301: FULL_BY_DEFAULT: description "use full/deep by default" — ambiguous whether it flags the param name or the default value
module Master
  module Backlog
    module Stubs
      module AB
        class AB301
          ID = "AB301".freeze
          DESCRIPTION = "FULL_BY_DEFAULT: description \"use full/deep by default\" — ambiguous whether it flags the param name or the default value; clarify: \"flag any method/flag parameter named shallow|standard|lite|basic|quick\"".freeze
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
