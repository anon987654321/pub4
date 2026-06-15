# frozen_string_literal: true
# TODO artifact Z405: Replace `next []` with `return []` in non-block contexts: `next` in a method body (not a block) is confusing — 3 instanc
module Master
  module Backlog
    module Stubs
      module Z
        class Z405
          ID = "Z405".freeze
          DESCRIPTION = "Replace `next []` with `return []` in non-block contexts: `next` in a method body (not a block) is confusing — 3 instances in js_rules.rb".freeze
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
