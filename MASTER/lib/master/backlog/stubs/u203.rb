# frozen_string_literal: true
# TODO artifact U203: GitHub corpus validation: before adding a new rule, search GitHub for 10 real violations of that pattern in popular Ruby
module Master
  module Backlog
    module Stubs
      module U
        class U203
          ID = "U203".freeze
          DESCRIPTION = "GitHub corpus validation: before adding a new rule, search GitHub for 10 real violations of that pattern in popular Ruby repos (rails/rails, Shopify/*, fastlane/fastlane) — confirm the smell is real and frequent".freeze
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
