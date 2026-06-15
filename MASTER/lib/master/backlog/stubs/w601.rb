# frozen_string_literal: true
# TODO artifact W601: Add `manifestations:` map to every rule in rules.yml: for each medium (ruby, yaml, prose, css, html, cli, design) descri
module Master
  module Backlog
    module Stubs
      module W
        class W601
          ID = "W601".freeze
          DESCRIPTION = "Add `manifestations:` map to every rule in rules.yml: for each medium (ruby, yaml, prose, css, html, cli, design) describe how the principle shows in that medium — currently rules are code-only".freeze
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
