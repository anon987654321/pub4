# frozen_string_literal: true

module Master
  module Ground
    # Detects version drift between YAML data and the readers that consume it.
    class SchemaCheck
      EXPECTED = {
        "council.yml" => 1,
        "limits.yml" => 1,
        "models.yml" => 1,
        "patterns.yml" => 1,
        "personas.yml" => 1,
        "providers.yml" => 1,
        "rules.yml" => 1,
        "soul.yml" => 1,
      }.freeze

      Mismatch = Data.define(:file, :expected, :actual)

      def self.verify!(root: Master::ROOT) = new(root:).verify!

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def verify!
        drift = check
        return Result.ok(:clean) if drift.empty?

        details = drift.map do |item|
          actual = item.actual.nil? ? "(missing)" : "v#{item.actual}"
          "  #{item.file}: expected v#{item.expected}, found #{actual}"
        end
        Result.err(["schema_check: drift detected:", *details].join("\n"), category: :validation)
      end

      def check
        EXPECTED.filter_map do |file, expected|
          actual = declared_version(file)
          Mismatch.new(file:, expected:, actual:) unless actual == expected
        end
      end

      private

      def declared_version(filename)
        path = File.join(@root, "data", filename)
        return unless File.readable?(path)

        data = Master.load_yaml(path)
        data["schema"] if data.is_a?(Hash)
      end
    end
  end
end
