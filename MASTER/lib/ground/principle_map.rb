# frozen_string_literal: true

require_relative "principle_map/queries"

module Master
  module Ground
    # Runtime map of fossil master.yml principles → live scan rule IDs + operations.
    # Loaded from data/principle_map.yml; enforced by SelfTest and /map.
    class PrincipleMap
      include Queries

      PATH = File.join(Master::DATA, "principle_map.yml").freeze

      Entry = Data.define(:id, :meaning, :detects, :severity, :confidence, :operation, :rule_ids, :status, :tags, :immutable)

      def self.load(root: Master::ROOT)
        new(root: root)
      end

      def initialize(root: Master::ROOT)
        @root = root
        @data = load_data
      end

      def principles
        @principles ||= build_entries
      end

      def clusters
        @data["clusters"] || {}
      end

      def version
        @data["version"].to_s
      end

      # Integrity: covered entries must resolve to registered RuleDSL ids when registry loaded.
      def integrity(registered_rule_ids: nil)
        registered = Array(registered_rule_ids).map { |id| id.to_s.upcase }.to_set
        findings = []
        principles.each_value do |entry|
          if entry.status == "covered" && entry.rule_ids.empty?
            findings << "covered principle #{entry.id} has no rule_ids"
          end
          next if registered.empty?

          entry.rule_ids.each do |rid|
            next if registered.include?(rid.to_s.upcase)

            findings << "principle #{entry.id} maps to unknown rule #{rid}"
          end
        end
        findings
      end

      def summary_line
        c = covered.size
        g = gaps.size
        a = aesthetic.size
        "principle_map #{version}: #{principles.size} principles (#{c} covered, #{g} gap, #{a} aesthetic/ui)"
      end

      private

      def load_data
        path = File.join(@root, "data", "principle_map.yml")
        path = PATH unless File.file?(path)
        Master.load_yaml(path, default: {}) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PrincipleMap.load_data")
        {}
      end

      def build_entries
        raw = @data["principles"] || {}
        raw.each_with_object({}) do |(id, body), acc|
          next unless body.is_a?(Hash)

          acc[id.to_s] = Entry.new(
            id: id.to_s,
            meaning: body["meaning"].to_s,
            detects: body["detects"],
            severity: body["severity"].to_s,
            confidence: body["confidence"].to_f,
            operation: body["operation"],
            rule_ids: Array(body["rule_ids"]).map(&:to_s),
            status: body["status"].to_s,
            tags: Array(body["tags"]).map(&:to_s),
            immutable: !!body["immutable"]
          )
        end
      end
    end
  end
end
