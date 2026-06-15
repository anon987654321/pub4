# frozen_string_literal: true
# TODO artifact AB502: soul.yml negotiable.default_model and data/models.yml default_tier use different model ID formats — soul.yml uses shorth
module Master
  module Backlog
    module Stubs
      module AB
        class AB502
          ID = "AB502".freeze
          DESCRIPTION = "soul.yml negotiable.default_model and data/models.yml default_tier use different model ID formats — soul.yml uses shorthand (\"claude-opus-4-7\"), models.yml uses full API path; normalize to one canonical format".freeze
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
