# frozen_string_literal: true
# TODO artifact AF402: `bullet_use: exception_not_default` — prose for reports, bullets only for ≥4 parallel items; match Claude's default-styl
module Master
  module Backlog
    module Stubs
      module AF
        class AF402
          ID = "AF402".freeze
          DESCRIPTION = "`bullet_use: exception_not_default` — prose for reports, bullets only for ≥4 parallel items; match Claude's default-styles.md".freeze
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
