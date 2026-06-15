# frozen_string_literal: true
# TODO artifact AB504: ruby_style.yml defines max_method_lines: 10 but SmallFunctionsRule uses MAX: 20 — two different "max" values for the sam
module Master
  module Backlog
    module Stubs
      module AB
        class AB504
          ID = "AB504".freeze
          DESCRIPTION = "ruby_style.yml defines max_method_lines: 10 but SmallFunctionsRule uses MAX: 20 — two different \"max\" values for the same concept; align or document the distinction (ideal vs hard limit)".freeze
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
