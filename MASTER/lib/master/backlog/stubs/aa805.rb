# frozen_string_literal: true
# TODO artifact AA805: Struct for value objects: Finding is a Hash — convert to `Finding = Struct.new(:rule_id, :line, :message, :severity, key
module Master
  module Backlog
    module Stubs
      module AA
        class AA805
          ID = "AA805".freeze
          DESCRIPTION = "Struct for value objects: Finding is a Hash — convert to `Finding = Struct.new(:rule_id, :line, :message, :severity, keyword_init: true)` — type-safe, inspectable, comparable".freeze
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
