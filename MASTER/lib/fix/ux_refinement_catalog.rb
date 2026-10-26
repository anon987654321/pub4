# frozen_string_literal: true

require "digest"
require "yaml"

module Master
  module Fix
    class UXRefinementCatalog
      PATH = File.expand_path("../../data/ux_refinements.yml", __dir__)
      EXPECTED_COUNT = 90
      TREE_NAMES = %w[MASTER RAILS OPENBSD STUDIO].freeze
      AREA_NAMES = %w[input terminal diagnostics command_help browser_recovery visual_accessibility].freeze
      PROOF_TYPES = %w[accessibility browser source terminal unit visual].freeze

      def self.load(path: PATH)
        payload = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
        validate!(payload)
        payload
      end

      def self.validate!(payload)
        raise ArgumentError, "UX catalog must be a mapping" unless payload.is_a?(Hash)
        rows = payload["refinements"]
        raise ArgumentError, "UX catalog must contain exactly #{EXPECTED_COUNT} records" unless rows.is_a?(Array) && rows.size == EXPECTED_COUNT
        ids = rows.map { |row| row.is_a?(Hash) ? row["id"].to_s : "" }
        expected_ids = (1..EXPECTED_COUNT).map { |number| format("UX%03d", number) }
        raise ArgumentError, "UX catalog IDs must be the ordered UX001–UX090 sequence" unless ids == expected_ids
        raise ArgumentError, "UX catalog expected_count disagrees" unless payload["expected_count"] == EXPECTED_COUNT
        rows.each do |row|
          %w[id area title owner_trees proof contract state].each do |field|
            raise ArgumentError, "UX catalog row missing #{field}" if row[field].to_s.strip.empty?
          end
          raise ArgumentError, "UX catalog row has no valid owner tree" unless row["owner_trees"].is_a?(Array) &&
            row["owner_trees"].any? && (row["owner_trees"] - TREE_NAMES).empty?
          raise ArgumentError, "UX catalog row must be owned by MASTER" unless row["owner_trees"].include?("MASTER")
          raise ArgumentError, "UX catalog row has unknown area" unless AREA_NAMES.include?(row["area"])
          raise ArgumentError, "UX catalog row has no valid proof type" unless row["proof"].is_a?(Array) &&
            row["proof"].any? && (row["proof"] - PROOF_TYPES).empty?
          raise ArgumentError, "UX catalog rows remain acceptance targets, not completed work" unless row["state"] == "acceptance_required"
        end
        missing_areas = AREA_NAMES - rows.map { |row| row["area"] }.uniq
        raise ArgumentError, "UX catalog missing areas: #{missing_areas.join(",")}" unless missing_areas.empty?
        true
      end

      def self.manifest(path: PATH)
        payload = load(path:)
        rows = payload.fetch("refinements")
        {
          "catalogue_id" => payload.fetch("catalogue_id"),
          "schema" => payload.fetch("schema"),
          "expected_count" => payload.fetch("expected_count"),
          "loaded_count" => rows.size,
          "sha256" => Digest::SHA256.file(path).hexdigest,
          "areas" => rows.map { |row| row.fetch("area") }.uniq,
          "by_area" => rows.group_by { |row| row.fetch("area") }.transform_values(&:size).sort.to_h,
          "by_owner_tree" => TREE_NAMES.to_h { |tree| [tree, rows.count { |row| row.fetch("owner_trees").include?(tree) }] },
          "by_proof_type" => rows.flat_map { |row| row.fetch("proof") }.tally.sort.to_h,
          "acceptance_required_count" => rows.count { |row| row.fetch("state") == "acceptance_required" },
          "owner_trees" => TREE_NAMES,
          "state_semantics" => "acceptance_required is not implementation evidence",
        }
      end

      def self.prompt_context(target:, root: Master::REPO_ROOT, path: PATH)
        payload = load(path:)
        base = File.expand_path(root)
        value = File.expand_path(target, base)
        return "" unless value == base || value.start_with?(base + File::SEPARATOR)
        relative = value == base ? "" : value.delete_prefix(base + File::SEPARATOR)
        tree = relative.split(File::SEPARATOR).first.to_s
        rows = if relative.empty?
                 payload.fetch("refinements")
               else
                 payload.fetch("refinements").select { |row| Array(row["owner_trees"]).include?(tree) }
               end
        return "" if rows.empty?
        lines = [
          "UX REFINEMENT ACCEPTANCE CONTRACT",
          "Canonical inventory: MASTER/data/ux_refinements.yml (#{rows.size} applicable rows; the full catalogue contains #{EXPECTED_COUNT}).",
          "These are acceptance targets, not evidence that the behavior exists. Inspect the relevant owner and add/run the declared proof; never claim completion from this list alone.",
          "Keep one canonical Ruby REPL prompt. The face is a presentation adapter, never a second authority. Preserve source and operator-owned values; do not apply unrelated visual items blindly."
        ]
        rows.each do |row|
          lines << "#{row.fetch("id")} [#{row.fetch("area")}] #{row.fetch("title")}: #{row.fetch("contract")} Proof=#{Array(row.fetch("proof")).join("+")}."
        end
        lines.join("\n")
      end
    end
  end
end
