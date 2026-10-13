# frozen_string_literal: true

require_relative "lib/fix/kernel"

module Master
  module Fix
    module Laws
      # Canonical core law list for the primitive kernel. Existing executable
      # law packs remain loaded through the legacy /fix adapter until each rule
      # has an equivalent predicate, repair and bad/good proof in this registry.
      LAWS = [
        Kernel::Law.new(
          name: "no_sacred_path_changed",
          sacred: true,
          automatic: false,
          check: lambda { |observation|
            (observation.deleted_paths + observation.modified_paths).any? do |path|
              observation.sacred_path?(path)
            end
          },
          repair: nil
        )
      ].freeze
    end
  end
end
