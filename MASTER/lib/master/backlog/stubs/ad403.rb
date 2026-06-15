# frozen_string_literal: true
# TODO artifact AD403: Offer exactly one next action, not a menu: "Run /fix to apply 2 autofixes" not "You could run /fix, or review the findin
module Master
  module Backlog
    module Stubs
      module AD
        class AD403
          ID = "AD403".freeze
          DESCRIPTION = "Offer exactly one next action, not a menu: \"Run /fix to apply 2 autofixes\" not \"You could run /fix, or review the findings, or…\"".freeze
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
