# frozen_string_literal: true

require "yaml"

module Master
  # Parser and structural validator for the normative flat law catalogue.
  #
  # This class validates identities, parentage and declared metadata. It does
  # not claim that a named mechanical adapter has executed; implementation
  # coverage is measured separately by the runtime law audit.
  class FlatLawCatalogue
    class Invalid < StandardError; end

    SCOPE_FIELDS = %w[applies_to domain path path_pattern exclude].freeze
    LEGACY_RANK_FIELDS = %w[priority tier].freeze
    SEVERITIES = %w[info warning error critical veto].freeze
    RESOLUTIONS = %w[automatic review never].freeze
    MODALITY_COVERAGE = %w[deterministic semantic].freeze
    METADATA_PREFIXES = %w[KIND_ RATCHET_ LINT_ META_].freeze

    class << self
      def load(root: Master::ROOT)
        document = Master.laws_document(root:)
        validate!(document)
        document
      end

      def entries(document)
        raise Invalid, "laws.yml must be a non-empty mapping" unless document.is_a?(Hash)

        document.filter_map do |id, row|
          row.merge("id" => id.to_s) if row.is_a?(Hash) && row["statement"].is_a?(String)
        end
      end

      def validate!(document)
        rows = entries(document)
        raise Invalid, "laws.yml declares no flat laws" if rows.empty?

        validate_ids!(rows)
        validate_precedence_nodes!(rows)
        validate_relationships!(rows)
        validate_vocabulary!(document, rows)
        validate_resolutions!(rows)
        validate_special_metadata!(rows)
        validate_protected_paths!(rows)
        validate_invariant_modalities!(rows)
        true
      end

      private

      def validate_ids!(rows)
        ids = rows.map { |row| row.fetch("id") }
        invalid = ids.reject { |id| id.match?(/\A[A-Z][A-Za-z0-9_]*\z/) }
        raise Invalid, "invalid law id(s): #{invalid.join(', ')}" unless invalid.empty?

        collisions = ids.group_by(&:downcase).select { |_id, names| names.size > 1 }.keys
        raise Invalid, "case-insensitive law id collision(s): #{collisions.join(', ')}" unless collisions.empty?
      end

      def validate_precedence_nodes!(rows)
        node_rows = rows.select { |row| row["node"] }
        declared = node_rows.map { |row| row["node"].to_s }
        valid = node_rows.all? { |row| row.fetch("id").downcase == row["node"].to_s }
        unless declared.size == 9 && declared.uniq == declared && valid &&
               declared.all? { |node| node.match?(/\A[a-z][a-z0-9_]*\z/) }
          raise Invalid, "laws.yml must declare nine unique invariant nodes whose ids match their node names"
        end
      end

      def validate_relationships!(rows)
        index = rows.to_h { |row| [row.fetch("id"), row] }
        rows.each do |row|
          id = row.fetch("id")
          fields = row.keys.map(&:to_s)
          scopes = SCOPE_FIELDS & fields
          raise Invalid, "#{id} contains forbidden scope field(s): #{scopes.join(', ')}" unless scopes.empty?
          legacy = LEGACY_RANK_FIELDS & fields
          raise Invalid, "#{id} contains retired ranking field(s): #{legacy.join(', ')}" unless legacy.empty?

          parent = row["parent"]
          root = row["root"]
          node = row["node"]
          if parent
            raise Invalid, "#{id} cannot declare parent and root/node together" if root || node
            raise Invalid, "#{id} names missing parent #{parent}" unless index.key?(parent.to_s)
            raise Invalid, "#{id} cannot parent itself" if parent.to_s == id
          else
            raise Invalid, "#{id} must declare exactly one root or node" unless (!!root ^ !!node)
          end

          statement = row["statement"].to_s.strip
          raise Invalid, "#{id} has an empty statement" if statement.empty?
        end

        visiting = {}
        visited = {}
        visit = lambda do |id|
          raise Invalid, "law parent cycle reaches #{id}" if visiting[id]
          return if visited[id]

          visiting[id] = true
          parent = index.fetch(id)["parent"]
          visit.call(parent.to_s) if parent
          visiting.delete(id)
          visited[id] = true
        end
        index.each_key { |id| visit.call(id) }
      end

      def validate_vocabulary!(document, rows)
        severity_values = Array(document.dig("SEVERITY_VOCABULARY", "values")).map(&:to_s)
        raise Invalid, "SEVERITY_VOCABULARY must declare #{SEVERITIES.join(', ')}" unless severity_values.sort == SEVERITIES.sort

        roots = Array(document.dig("ROOTS_VOCABULARY", "values")).map(&:to_s)
        used = rows.filter_map { |row| row["root"]&.to_s }.uniq
        missing = used - roots
        raise Invalid, "ROOTS_VOCABULARY is missing root(s): #{missing.join(', ')}" unless missing.empty?

        rows.each do |row|
          severity = row["severity"]
          next if severity.nil? || severity_values.include?(severity.to_s)

          raise Invalid, "#{row.fetch("id")} has unknown severity #{severity.inspect}"
        end
      end

      def validate_resolutions!(rows)
        rows.each do |row|
          id = row.fetch("id")
          resolution = row["resolution"]
          next if resolution.nil?

          raise Invalid, "#{id} has unknown resolution #{resolution.inspect}" unless RESOLUTIONS.include?(resolution.to_s)
          if resolution.to_s == "automatic" && row["proof"].to_s.strip.empty?
            raise Invalid, "#{id} is automatic but names no proof fixture"
          end
        end
      end

      def validate_invariant_modalities!(rows)
        rows.select { |row| row["node"] }.each do |row|
          id = row.fetch("id")
          %w[mechanical semantic].each do |modality|
            value = row[modality]
            raise Invalid, "#{id} must declare #{modality} enforcement" unless
              value.is_a?(String) && !value.strip.empty?
          end

          mode = row["coverage_mode"].to_s
          raise Invalid, "#{id} has no valid coverage_mode" unless MODALITY_COVERAGE.include?(mode)
          raise Invalid, "#{id} must declare enforcement: declared" unless row["enforcement"] == "declared"
          if mode == "deterministic" && Array(row["detector_ids"]).empty?
            raise Invalid, "#{id} deterministic coverage must name detector_ids"
          end
        end
      end

      def validate_protected_paths!(rows)
        entry = rows.find { |row| row.fetch("id") == "SACRED_AUTHORSHIP" }
        raise Invalid, "SACRED_AUTHORSHIP is required" unless entry
        if entry.key?("protected_paths")
          raise Invalid, "protected paths belong to soul.yml#absolute.sacred_paths, not laws.yml"
        end
      end

      def validate_special_metadata!(rows)
        rows.each do |row|
          id = row.fetch("id")
          if id.start_with?("RATCHET_")
            raise Invalid, "#{id} must declare may_only: fall" unless row["may_only"] == "fall"
            raise Invalid, "#{id} must declare a numeric or scalar value" unless row.key?("value")
          elsif id.start_with?("LINT_")
            raise Invalid, "#{id} must declare an enforcement surface" if row["enforcement"].to_s.strip.empty?
          elsif id.start_with?("KIND_") && row.key?("default_resolution") && row["expiry"].to_s.strip.empty?
            raise Invalid, "#{id} must declare expiry"
          end
        end
      end
    end
  end
end
