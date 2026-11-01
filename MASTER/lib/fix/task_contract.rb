# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Validated task intent and preservation boundaries. This is procedure,
    # not a second source of Law.
    module TaskContract
      class Invalid < StandardError; end

      PATH = File.expand_path("../../data/task_contract.yml", __dir__).freeze
      REQUIRED = %w[intent scope preserve proof].freeze

      Contract = Data.define(:schema, :intent, :scope, :preserve, :proof) do
        def to_h
          {
            "schema" => schema,
            "intent" => intent,
            "scope" => scope,
            "preserve" => preserve,
            "proof" => proof,
          }
        end
      end

      module_function

      def template(path: PATH)
        schema = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        raise Invalid, "task contract schema must be version 1" unless schema.is_a?(Hash) && schema["schema"] == 1
        schema
      rescue Psych::Exception => error
        raise Invalid, "task contract schema is unreadable: #{error.message}"
      end

      def build(attributes, path: PATH)
        raise Invalid, "task contract must be a mapping" unless attributes.is_a?(Hash)
        input = attributes.to_h { |key, value| [key.to_s, value] }
        missing = REQUIRED - input.keys
        raise Invalid, "task contract is missing: #{missing.join(', ')}" unless missing.empty?
        unknown = input.keys - REQUIRED
        raise Invalid, "task contract has unknown fields: #{unknown.join(', ')}" unless unknown.empty?

        schema = template(path:)
        intent = input.fetch("intent").to_s
        policy = schema.fetch("intents")[intent]
        raise Invalid, "unknown task intent: #{intent.inspect}" unless policy.is_a?(Hash)

        scope = Array(input.fetch("scope")).map { |item| safe_path(item) }.uniq.sort
        raise Invalid, "task scope must name at least one repository-relative path" if scope.empty?
        allowed_preservation = Array(schema.fetch("preservation_dimensions")).map(&:to_s)
        preservation = Array(input.fetch("preserve")).map(&:to_s)
        unknown_preservation = preservation - allowed_preservation
        unless unknown_preservation.empty?
          raise Invalid, "unknown preservation dimension(s): #{unknown_preservation.join(', ')}"
        end
        required_preservation = Array(policy.fetch("must_preserve")).map(&:to_s)
        proof = Array(input.fetch("proof")).map(&:to_s)
        allowed_proof = Array(schema.fetch("proof_types")).map(&:to_s)
        unknown_proof = proof - allowed_proof
        raise Invalid, "unknown proof type(s): #{unknown_proof.join(', ')}" unless unknown_proof.empty?

        Contract.new(
          schema.fetch("schema"),
          intent.freeze,
          scope.freeze,
          (preservation + required_preservation).uniq.sort.freeze,
          (proof + Array(schema.fetch("common_proof")).map(&:to_s)).uniq.sort.freeze,
        ).freeze
      end

      def coerce(value, path: PATH)
        raise Invalid, "task contract must be a mapping or TaskContract::Contract" unless value.respond_to?(:to_h)

        attributes = value.to_h.transform_keys(&:to_s)
        version = attributes.delete("schema")
        raise Invalid, "unsupported task contract version: #{version.inspect}" if version && version != 1
        build(attributes, path:)
      end

      def covers?(path, scope:)
        candidate = path.to_s
        Array(scope).any? do |entry|
          pattern = entry.to_s
          if pattern.end_with?("/**")
            prefix = pattern.delete_suffix("/**").delete_suffix("/")
            next true if candidate == prefix || candidate.start_with?("#{prefix}/")
          end
          prefix = pattern.delete_suffix("/")
          next true if candidate == prefix
          next true if !pattern.match?(/[*?\[\]{}]/) && candidate.start_with?("#{prefix}/")

          File.fnmatch?(pattern, candidate, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      def agent_schema(path: PATH)
        schema = template(path:)
        {
          "schema" => schema.fetch("schema"),
          "required_fields" => schema.fetch("required_fields"),
          "common_proof" => schema.fetch("common_proof"),
          "intents" => schema.fetch("intents").transform_values { |value| value.slice("description", "must_preserve") },
        }
      end

      def prompt(path: PATH)
        schema = template(path:)
        rows = schema.fetch("intents").map do |name, policy|
          "  #{name}: #{policy.fetch("description")} Must preserve: #{Array(policy.fetch("must_preserve")).join(", ")}"
        end
        [
          "Use a task contract before planning edits. Required fields: #{REQUIRED.join(", ")}.",
          "Intent is explicit; choose the narrowest mode supported by the request. Do not silently promote a content edit into a redesign.",
          *rows,
          "Scope paths are repository-relative. Preserve all mandatory dimensions for the selected intent.",
          "Proof always includes baseline hashes, a path-scoped diff and a Law assessment. Add relevant tests, rendered/runtime evidence, accessibility review, citations or human review.",
          "If a required measurement is absent or a format has no verifier, report INCONCLUSIVE or NOT_RUN; do not infer PASS.",
          "Schema: MASTER/data/task_contract.yml.",
        ].join("\n")
      end

      def safe_path(value)
        path = value.to_s.strip.delete_suffix("/")
        segments = path.split("/")
        if path.empty? || path.start_with?("/", "~") || path.include?("\\") || path.include?("\0") ||
           segments.any? { |segment| segment.empty? || segment == "." || segment == ".." } ||
           path.match?(/\A[A-Za-z]:/)
          raise Invalid, "task scope path must be repository-relative: #{path.inspect}"
        end
        path
      end
    end
  end
end
