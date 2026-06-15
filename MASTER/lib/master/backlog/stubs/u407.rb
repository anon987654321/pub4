# frozen_string_literal: true
# TODO artifact U407: Require findings to have "why this matters" annotation beyond the rule message — e.g., "CQS violation here makes this me
module Master
  module Backlog
    module Stubs
      module U
        class U407
          ID = "U407".freeze
          DESCRIPTION = "Require findings to have \"why this matters\" annotation beyond the rule message — e.g., \"CQS violation here makes this method untestable because…\"".freeze
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
