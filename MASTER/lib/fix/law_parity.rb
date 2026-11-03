# frozen_string_literal: true

module Master
  module Fix
    # Checks that each constitutional node declares both enforcement
    # modalities. This validates the contract, not the quality or execution of
    # the named detectors; LawRegistryAudit and actual test evidence own that.
    class LawParity
      LAWS_PATH = File.join(Master::ROOT, "data", "laws.yml").freeze
      COVERAGE_MODES = %w[deterministic semantic].freeze

      Gap = Data.define(:id, :missing, :reason)

      def initialize(root: Master::ROOT, laws_path: nil)
        @root = File.expand_path(Master.master_root(root:))
        @laws_file = laws_path || File.join(@root, "data", "laws.yml")
      end

      def call
        document = document_to_judge
        Master::FlatLawCatalogue.validate!(document)
        nodes = Master::FlatLawCatalogue.entries(document).select { |entry| entry["node"] }

        nodes.flat_map do |entry|
          missing = []
          %w[mechanical semantic].each do |modality|
            missing << modality if entry[modality].to_s.strip.empty?
          end
          mode = entry["coverage_mode"].to_s
          missing << "coverage_mode" unless COVERAGE_MODES.include?(mode)
          missing << "detector_ids" if mode == "deterministic" && Array(entry["detector_ids"]).empty?
          # flat_map keeps nil elements, and a complete contract must not look
          # like a gap: contribute an empty list, not a bare next.
          next [] if missing.empty?

          [Gap.new(
            id: entry.fetch("id"),
            missing: missing.freeze,
            reason: "missing declared contract field(s): #{missing.join(", ")}",
          )]
        end
      end

      def ok? = call.empty?

      def report
        gaps = call
        if gaps.empty?
          entries = Master::FlatLawCatalogue.entries(document_to_judge).select { |entry| entry["node"] }
          ids = entries.map { |entry| entry.fetch("id") }
          "law_parity: declarations complete (#{ids.size} ordered invariant laws; execution evidence measured separately)"
        else
          lines = gaps.map { |gap| "  #{gap.id}: #{gap.reason}" }
          "law_parity: #{gaps.size} declaration gap(s)\n#{lines.join("\n")}"
        end
      end

      # A fixture path is read as content through the shared parser; the
      # default goes through the whole-document accessor. The two live apart
      # so the fixture read never sits beside the default path literal.
      def document_to_judge
        return Master.parse_yaml_content(File.read(@laws_file), source: @laws_file) if @laws_file

        Master.laws_document(root: @root)
      end
    end
  end
end
