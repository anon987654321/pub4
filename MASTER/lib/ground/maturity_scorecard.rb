# frozen_string_literal: true

require "date"

module Master
  module Ground
    # Loads data/maturity.yml -- a maturity scorecard matching OpenClaw's
    # taxonomy.yaml. See that file's header for the full rationale
    # (SURFACE_ERRORS_FIRST / anti_simulation: prove completion,
    # don't just claim it).
    class MaturityScorecard
      STATUSES = %w[verified smoke broken].freeze
      PATH = File.join(Master::DATA, "maturity.yml").freeze
      # A verification has a shelf life, and this file exists to say that a
      # claim is not evidence. Thirty days is the interval over which this
      # tree's own recorded figures have repeatedly stopped being true — whole
      # sections of the register go stale inside a fortnight — so a row whose
      # evidence is older than a month is reported as a claim again.
      EVIDENCE_SHELF_LIFE_DAYS = 30

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

      def stale(today: Date.today)
        subsystems.select { |entry| stale?(entry, today) }
      end

      # Printed by bin/doctor. The stale count leads the counts it qualifies,
      # because eight rows reading `verified` off evidence nobody has re-taken
      # is the claim this scorecard was written to refuse.
      def summary_line(today: Date.today)
        counts = STATUSES.to_h { |s| [s, by_status(s).size] }
        overdue = stale(today:).size
        "maturity: #{subsystems.size} subsystems tracked " \
          "(#{counts.map { |s, n| "#{s}=#{n}" }.join(" ")}), " \
          "#{overdue} unchecked for over #{EVIDENCE_SHELF_LIFE_DAYS} days"
      end

      private

      def stale?(entry, today)
        checked = Date.parse(entry.last_checked)
        (today - checked).to_i > EVIDENCE_SHELF_LIFE_DAYS
      rescue Date::Error, TypeError
        true
      end

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
