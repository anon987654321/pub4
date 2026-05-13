# frozen_string_literal: true

require "yaml"

module Master
  module Runtime
    class StaleNamespaceAudit
      DEFAULT_PATHS = %w[
        lib
        test
        web
        exe
        docs
      ].freeze

      def initialize(root:, registry: nil)
        @root = root
        @registry = registry || File.join(root, "data", "stale_namespaces.yml")
      end

      def violations
        rules.flat_map do |rule|
          scan(rule)
        end
      end

      def clean?
        violations.empty?
      end

      private

      def rules
        YAML.load_file(@registry).fetch("stale_constants", [])
      rescue StandardError
        []
      end

      def scan(rule)
        old = rule["old"]
        replacement = rule["new"]

        DEFAULT_PATHS.flat_map do |path|
          absolute = File.join(@root, path)
          next [] unless Dir.exist?(absolute)

          Dir.glob(File.join(absolute, "**", "*"))
             .select { |f| File.file?(f) }
             .filter_map do |file|
            next unless File.read(file).include?(old)

            {
              file: file,
              stale: old,
              replacement: replacement
            }
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
