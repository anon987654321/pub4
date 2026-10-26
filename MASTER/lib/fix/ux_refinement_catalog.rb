# frozen_string_literal: true

require "digest"
require "yaml"

module Master
  module Fix
    class UXRefinementCatalog
      PATH = File.expand_path("../../data/ux_refinements.yml", __dir__)
      EXPECTED_COUNT = 90
      TREE_NAMES = %w[MASTER RAILS OPENBSD STUDIO].freeze

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
        raise ArgumentError, "UX catalog IDs must be unique and nonblank" if ids.any?(&:empty?) || ids.uniq.size != ids.size
        raise ArgumentError, "UX catalog expected_count disagrees" unless payload["expected_count"] == EXPECTED_COUNT
        rows.each do |row|
          %w[id area title owner_trees proof contract state].each do |field|
            raise ArgumentError, "UX catalog row missing #{field}" if row[field].to_s.strip.empty?
          end
          raise ArgumentError, "UX catalog row has no valid owner tree" if Array(row["owner_trees"]).empty? ||
            (Array(row["owner_trees"]) - TREE_NAMES).any?
          raise ArgumentError, "UX catalog row has no proof type" if Array(row["proof"]).empty?
        end
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
