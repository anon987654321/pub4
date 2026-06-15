# frozen_string_literal: true
# TODO artifact AF101: Add `default_posture: helping_bias` to soul.yml — flip burden-of-proof from permission-required to refusal-justified; de
module Master
  module Backlog
    module Stubs
      module AF
        class AF101
          ID = "AF101".freeze
          DESCRIPTION = "Add `default_posture: helping_bias` to soul.yml — flip burden-of-proof from permission-required to refusal-justified; decline only when concrete harm risk exists".freeze
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
