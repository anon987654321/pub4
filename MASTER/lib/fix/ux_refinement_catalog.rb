# frozen_string_literal: true

require "digest"
require "yaml"

module Master
  module Fix
    class UXRefinementCatalog
      PATH = File.expand_path("../../data/ux_refinements.yml", __dir__)
      EXPECTED_COUNT = 90
      SCHEMA_VERSION = 1
      CATALOGUE_ID = "MASTER_UX_REFINEMENTS"
      TREE_NAMES = MasterPaths::TREES
      AREA_NAMES = %w[input terminal diagnostics command_help browser_recovery visual_accessibility].freeze
      PROOF_TYPES = %w[accessibility browser source terminal unit visual].freeze

      def self.load(path: PATH)
        payload = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
        validate!(payload)
        payload
      end

      def self.validate!(payload)
        raise ArgumentError, "UX catalog must be a mapping" unless payload.is_a?(Hash)
        raise ArgumentError, "UX catalog schema must be #{SCHEMA_VERSION}" unless payload["schema"] == SCHEMA_VERSION
        raise ArgumentError, "UX catalog ID must be #{CATALOGUE_ID}" unless payload["catalogue_id"] == CATALOGUE_ID
        raise ArgumentError, "UX catalog must reference a canonical Law in MASTER/data/laws.yml" unless
          canonical_authority?(payload["authority"])
        policy = payload["evidence_policy"]
        raise ArgumentError, "UX catalog must declare an evidence policy" unless policy.is_a?(Hash)
        raise ArgumentError, "UX catalog implementation state must remain acceptance_required" unless
          policy["implementation_state"] == "acceptance_required"
        raise ArgumentError, "UX catalog completion rule must require owner evidence" unless
          policy["completion_rule"].to_s.match?(/only when .*records the required test or rendered\/runtime evidence/i)
        raise ArgumentError, "UX catalog must explicitly forbid simulated runtime proof" unless
          policy["no_simulation"].to_s.match?(/never counts as a passing runtime test/i)

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
          case row["state"]
          when "acceptance_required"
            # Open by design; source changes and inventory membership are not proof.
          when "verified"
            validate_evidence!(row)
          else
            raise ArgumentError, "UX catalog row has unknown state: #{row["state"]}"
          end
        end
        missing_areas = AREA_NAMES - rows.map { |row| row["area"] }.uniq
        raise ArgumentError, "UX catalog missing areas: #{missing_areas.join(",")}" unless missing_areas.empty?
        true
      end

      # A verified row is admissible only with real PASS receipts for every
      # declared proof type. Each receipt binds a local evidence artifact and its
      # digest to the exact source commit that was measured.
      def self.validate_evidence!(row)
        receipts = row["evidence"]
        raise ArgumentError, "#{row["id"]}: verified row needs evidence receipts" unless receipts.is_a?(Array) && receipts.any?

        proof_types = receipts.map do |receipt|
          raise ArgumentError, "#{row["id"]}: evidence receipt must be a mapping" unless receipt.is_a?(Hash)

          proof_type = receipt["proof_type"].to_s
          raise ArgumentError, "#{row["id"]}: evidence has undeclared proof type" unless row["proof"].include?(proof_type)
          raise ArgumentError, "#{row["id"]}: evidence result must be PASS" unless receipt["result"] == "PASS"

          location = receipt["location"].to_s.strip
          parts = location.split("/")
          safe_path = !location.empty? && !location.start_with?("/") && !location.match?(/\A[A-Za-z]:/) &&
            !location.include?("\\") && parts.none? { |part| part.empty? || part == "." || part == ".." }
          raise ArgumentError, "#{row["id"]}: evidence location must be a safe repository-relative path" unless safe_path

          raise ArgumentError, "#{row["id"]}: evidence needs a SHA-256 digest" unless receipt["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/i)
          raise ArgumentError, "#{row["id"]}: evidence needs a full commit SHA" unless receipt["commit"].to_s.match?(/\A[0-9a-f]{40}\z/i)
          proof_type
        end
        missing = Array(row["proof"]).map(&:to_s).uniq - proof_types.uniq
        raise ArgumentError, "#{row["id"]}: verified row is missing proof receipts for #{missing.join(",")}" unless missing.empty?

        true
      end

      # The authority in the inventory is a pointer to an existing canonical
      # Law, not a second copy of the Law's prose or rules.
      def self.canonical_authority?(value)
        match = value.to_s.match(%r{\AMASTER/data/laws\.yml#([a-z][a-z0-9_]*)\z})
        return false unless match

        laws_path = File.expand_path("../../data/laws.yml", __dir__)
        laws = YAML.safe_load_file(laws_path, permitted_classes: [], permitted_symbols: [], aliases: true)
        laws.key?(match[1])
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
          "verified_count" => rows.count { |row| row.fetch("state") == "verified" },
          "owner_trees" => TREE_NAMES,
          "state_semantics" => "acceptance_required is open; verified requires PASS receipts for every proof type, each bound to a commit and SHA-256",
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
          "Rows marked acceptance_required remain open. A verified row must carry PASS receipts for every declared proof type, each bound to a repository-relative evidence artifact, SHA-256 and exact commit. Never infer completion from inventory membership alone.",
          "Keep one canonical Ruby REPL prompt. The face is a presentation adapter, never a second authority. Preserve source and operator-owned values; do not apply unrelated visual items blindly."
        ]
        rows.each do |row|
          receipt_count = Array(row["evidence"]).size
          lines << "#{row.fetch("id")} [#{row.fetch("area")}; state=#{row.fetch("state")}] #{row.fetch("title")}: #{row.fetch("contract")} Proof=#{Array(row.fetch("proof")).join("+")}.#{row["state"] == "verified" ? " Verified receipts=#{receipt_count}." : ""}"
        end
        lines.join("\n")
      end
    end
  end
end
