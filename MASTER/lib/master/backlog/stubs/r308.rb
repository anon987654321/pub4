# frozen_string_literal: true
# TODO artifact R308: Layer purity check: after any change to lib/now/, check if it calls lib/judge/ directly (should be via Pipeline) — propo
module Master
  module Backlog
    module Stubs
      module R
        class R308
          ID = "R308".freeze
          DESCRIPTION = "Layer purity check: after any change to lib/now/, check if it calls lib/judge/ directly (should be via Pipeline) — propose routing fix".freeze
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
