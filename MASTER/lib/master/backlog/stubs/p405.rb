# frozen_string_literal: true
# TODO artifact P405: RuleLoop#best_candidate: rescan_candidate writes to Tempfile without extension — language detection in scan() returns ni
module Master
  module Backlog
    module Stubs
      module P
        class P405
          ID = "P405".freeze
          DESCRIPTION = "RuleLoop#best_candidate: rescan_candidate writes to Tempfile without extension — language detection in scan() returns nil, no rule applies — add extension suffix".freeze
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
