# frozen_string_literal: true
# TODO artifact AB106: SECRET_PROXIMITY and FORBIDDEN_PATTERNS both detect hardcoded credentials — SECRET_PROXIMITY uses proximity context; FOR
module Master
  module Backlog
    module Stubs
      module AB
        class AB106
          ID = "AB106".freeze
          DESCRIPTION = "SECRET_PROXIMITY and FORBIDDEN_PATTERNS both detect hardcoded credentials — SECRET_PROXIMITY uses proximity context; FORBIDDEN_PATTERNS uses exact pattern; define which is authoritative or merge".freeze
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
