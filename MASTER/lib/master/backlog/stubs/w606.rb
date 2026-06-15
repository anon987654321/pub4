# frozen_string_literal: true
# TODO artifact W606: Add medium detection to scanner: when scanning .md files, apply prose-manifestation rules; when scanning .css, apply CSS
module Master
  module Backlog
    module Stubs
      module W
        class W606
          ID = "W606".freeze
          DESCRIPTION = "Add medium detection to scanner: when scanning .md files, apply prose-manifestation rules; when scanning .css, apply CSS-manifestation rules — currently only Ruby rules applied universally".freeze
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
