# frozen_string_literal: true

module Master
  module Ground
    # Loads data/maturity.yml -- a maturity scorecard matching OpenClaw's
    # taxonomy.yaml. See that file's header for the full rationale
    # (SURFACE_ERRORS_FIRST / anti_simulation: prove completion,
    # don't just claim it).
    class MaturityScorecard
      STATUSES = %w[verified smoke broken].freeze
      PATH = File.join(Master::DATA, "maturity.yml").freeze

      Entry = Data.define(:id, :status, :meaning, :evidence, :last_checked)

      def self.load(root: Master::ROOT)
        new(root:)
      end

      def initialize(root: Master::ROOT)
        @root = root
        @data = load_data
      end

      def subsystems
        @subsystems ||= build_entries
      end

      def by_status(status)
        subsystems.select { |entry| entry.status == status.to_s }
      end

      def summary_line
        counts = STATUSES.to_h { |s| [s, by_status(s).size] }
        "maturity: #{subsystems.size} subsystems tracked (#{counts.map { |s, n| "#{s}=#{n}" }.join(" ")})"
      end

      private

      def load_data = Master.load_data_yaml(@root, "maturity.yml", PATH, context: "MaturityScorecard.load_data")

      def build_entries
        raw = @data["subsystems"] || {}
        raw.filter_map do |id, body|
          next unless body.is_a?(Hash)

          Entry.new(
            id: id.to_s,
            status: body["status"].to_s,
            meaning: body["meaning"].to_s,
            evidence: body["evidence"].to_s,
            last_checked: body["last_checked"].to_s,
          )
        end
      end
    end
  end
end
