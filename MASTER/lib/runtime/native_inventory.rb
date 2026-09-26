# frozen_string_literal: true

module Master
  module Runtime
    module NativeInventory
      module_function

      def specs
        Gem::Specification.to_a
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::NativeInventory.specs")
        []
      end

      def native?(spec)
        Array(spec.extensions).any?
      end

      def rows
        specs.filter_map do |spec|
          next unless native?(spec)

          {
            name: spec.name.to_s,
            version: spec.version.to_s,
            extensions: Array(spec.extensions).map(&:to_s).freeze,
            ractor_safety: ractor_safety(spec),
          }.freeze
        end
      end

      def ractor_safety(spec)
        metadata = spec.respond_to?(:metadata) ? spec.metadata : {}
        return "safe" if metadata["ractor_safe"].to_s == "true"
        return "unsafe" if metadata["ractor_safe"].to_s == "false"

        "unknown"
      end

      def snapshot
        native = rows
        {
          native_gems: native.size,
          unknown_ractor_safety: native.count { |row| row[:ractor_safety] == "unknown" },
          gems: native,
        }.freeze
      end
    end
  end
end
