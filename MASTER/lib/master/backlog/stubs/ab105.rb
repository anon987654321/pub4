# frozen_string_literal: true
# TODO artifact AB105: SMALL_FILES (SmallFilesRule B01, limit 300) and JS_MODULE_SIZE (js_rules, limit 300) are the same rule duplicated for di
module Master
  module Backlog
    module Stubs
      module AB
        class AB105
          ID = "AB105".freeze
          DESCRIPTION = "SMALL_FILES (SmallFilesRule B01, limit 300) and JS_MODULE_SIZE (js_rules, limit 300) are the same rule duplicated for different language labels — unify under one rule with medium-specific message".freeze
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
