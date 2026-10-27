# frozen_string_literal: true

require_relative "lib/fix/kernel"

module Master
  module Fix
    module Laws
      # Canonical core law list for the primitive kernel. Existing executable
      # law packs remain loaded through the legacy /fix adapter until each rule
      # has an equivalent predicate, repair and bad/good proof in this registry.
      # Optimistic "ready" from ENV alone — mirrors law/interface.rb
      # CAPABILITY_STATUS_MUST_BE_TRUTHFUL bad fixture. Kernel check is
      # observation-scoped so /fix cannot commit a status lie without the
      # primitive ledger noticing, even when the full scanner pack is shed.
      CAPABILITY_OPTIMISTIC_READY = %r{
        when\s+["']voice["'][^\n]*ENV\[
        .*?
        ["']ready["']
      }mx

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
          repair: nil,
        ),
        Kernel::Law.new(
          name: "CAPABILITY_STATUS_MUST_BE_TRUTHFUL",
          sacred: false,
          automatic: false,
          check: lambda { |observation|
            observation.modified_paths.any? do |path|
              file = observation.file(path)

              next false unless file && file.content

              file.content.match?(CAPABILITY_OPTIMISTIC_READY)
            end
          },
          repair: nil,
        ),
      ].freeze
    end
  end
end
