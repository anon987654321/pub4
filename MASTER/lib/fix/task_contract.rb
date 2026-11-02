# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Master
  module Fix
    # Validated task intent and preservation boundaries. This is procedure,
    # not a second source of Law.
    module TaskContract
      class Invalid < StandardError; end

      PATH = File.expand_path("../../data/task_contract.yml", __dir__).freeze
      REQUIRED = %w[intent scope preserve proof].freeze
      EVIDENCE_KEY = :master_fix_task_contract_preservation_evidence
      PLAN_KEY = :master_fix_task_contract_plan_digest
      MAX_PRESERVATION_ROWS = 256

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

      def build(attributes = nil, path: PATH, **keyword_attributes)
        if attributes.nil?
          attributes = keyword_attributes
        elsif keyword_attributes.any?
          raise Invalid, "task contract attributes must be passed as one mapping"
        end
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

      # The active contract is scoped to the synchronous Fix call. Nested calls
      # restore their caller's contract, and exceptions never leak it to later work.
      def current
        Thread.current[:master_fix_task_contract]
      end

      def with_current(value)
        previous = current
        previous_evidence = Thread.current[EVIDENCE_KEY]
        previous_plan = Thread.current[PLAN_KEY]
        contract = value.nil? ? nil : coerce(value)
        Thread.current[:master_fix_task_contract] = contract
        unless contract && previous == contract
          Thread.current[EVIDENCE_KEY] = []
          Thread.current[PLAN_KEY] = nil
        end
        yield
      ensure
        Thread.current[:master_fix_task_contract] = previous
        Thread.current[EVIDENCE_KEY] = previous_evidence
        Thread.current[PLAN_KEY] = previous_plan
      end

      # Bind runtime preservation receipts to the immutable FixPlan.
      def attach_plan!(digest)
        return unless current

        Thread.current[PLAN_KEY] = digest.to_s
      end

      def record_preservation!(path:, format:, before:, after:, result:, verifier: "artifact_preservation")
        contract = current
        return unless contract

        absolute = File.expand_path(path.to_s)
        repository = File.expand_path(defined?(Master::REPO_ROOT) ? Master::REPO_ROOT : File.expand_path("../../..", __dir__))
        relative = if absolute == repository
                     "."
                   elsif absolute.start_with?(repository + File::SEPARATOR)
                     absolute.delete_prefix(repository + File::SEPARATOR)
                   else
                     absolute
                   end
        value = result.to_h
        contract_digest = Digest::SHA256.hexdigest(JSON.generate(contract.to_h))
        row = {
          "path" => relative,
          "format" => format.to_s.downcase.delete_prefix("."),
          "intent" => contract.intent,
          "verifier" => verifier.to_s,
          "evidence_level" => verifier.to_s == "artifact_preservation" ? "source_level" : "runtime_or_external",
          "status" => (value[:status] || value["status"]).to_s,
          "checks" => Array(value[:checks] || value["checks"]).map(&:to_s),
          "reason" => (value[:reason] || value["reason"])&.to_s&.slice(0, 300),
          "before_sha256" => Digest::SHA256.hexdigest(before.to_s.b),
          "after_sha256" => Digest::SHA256.hexdigest(after.to_s.b),
          "contract_digest" => contract_digest,
          "plan_digest" => Thread.current[PLAN_KEY],
        }.compact
        rows = Thread.current[EVIDENCE_KEY] ||= []
        rows << row.freeze
        rows.shift while rows.size > MAX_PRESERVATION_ROWS
        row
      end

      # Source-level checks are never promoted into full rendered/runtime/
      # accessibility preservation proof.
      def preservation_evidence
        contract = current
        rows = Array(Thread.current[EVIDENCE_KEY])
        return { "status" => "not_measured", "results" => [] } unless contract

        statuses = rows.map { |row| row["status"] }
        status = if statuses.include?("FAIL")
                   "FAIL"
                 elsif rows.empty?
                   "not_measured"
                 elsif statuses.include?("INCONCLUSIVE") || rows.any? { |row| row["evidence_level"] == "source_level" }
                   "INCONCLUSIVE"
                 else
                   "PASS"
                 end
        {
          "status" => status,
          "contract_digest" => Digest::SHA256.hexdigest(JSON.generate(contract.to_h)),
          "plan_digest" => Thread.current[PLAN_KEY],
          "required_dimensions" => contract.preserve,
          "result_count" => rows.size,
          "results" => rows.dup,
          "reason" => "source-level checks do not prove rendered, runtime or accessibility preservation" if
            rows.any? { |row| row["evidence_level"] == "source_level" },
        }.compact
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
