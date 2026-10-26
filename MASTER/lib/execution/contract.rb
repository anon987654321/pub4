# frozen_string_literal: true

require "digest"
require "securerandom"
require "time"

module Master
  module Execution
    # Small shared contracts for lifecycle records. Workflow-specific policy
    # remains with its workflow; this module owns the accepted wire vocabulary.
    module Contract
      TERMINAL_STATES = %i[
        done plateau crash skip human_decision blocked inconclusive validation_failed
        delivery_failed timeout failed reloading cancelled unknown_outcome recovery_failed
      ].freeze

      EFFECT_OPERATIONS = %i[perform rollback compensation compensation_approval].freeze
      EVIDENCE_STATUSES = %i[verified failed inconclusive unavailable].freeze
      TOKEN = /\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,159}\z/
      KIND = /\A[a-z][a-z0-9_.-]{0,63}\z/
      SHA256 = /\A[0-9a-f]{64}\z/

      module_function

      def normalize_terminal_state(value)
        return nil if value.nil?

        state = value.to_s.downcase.to_sym
        TERMINAL_STATES.include?(state) ? state : nil
      end

      def token!(value, name)
        token = value.to_s
        raise ArgumentError, "#{name} must be a non-empty opaque token" unless TOKEN.match?(token)

        token.freeze
      end

      # Durable diagnostics carry correlation, not raw provider errors, prompts,
      # file paths or upstream response bodies. The caller retains the original
      # error locally for an actionable result.
      def diagnostic_fields(value, key: :error)
        return {} if value.nil?

        raw = value.to_s
        {
          "#{key}_digest".to_sym => Digest::SHA256.hexdigest(raw),
          "#{key}_bytes".to_sym => raw.bytesize
        }
      end

      EvidenceReference = Data.define(:id, :kind, :digest, :status, :verifier) do
        def initialize(id:, kind:, status:, verifier:, digest: nil)
          id = Contract.token!(id, "evidence id")
          kind = kind.to_s.downcase
          raise ArgumentError, "invalid evidence kind" unless Contract::KIND.match?(kind)

          digest = digest.to_s.downcase unless digest.nil?
          unless digest.nil? || Contract::SHA256.match?(digest)
            raise ArgumentError, "evidence digest must be a SHA-256 hex digest"
          end

          status = status.to_sym
          unless Contract::EVIDENCE_STATUSES.include?(status)
            raise ArgumentError, "unknown evidence status: #{status}"
          end

          verifier = Contract.token!(verifier, "evidence verifier")
          super(id:, kind: kind.freeze, digest: digest&.freeze, status:, verifier:)
        end

        # The reference records provenance, never the referenced private content.
        def to_h = { id:, kind:, digest:, status:, verifier: }.compact
      end

      # One normalized verifier outcome. It adapts existing check and proof
      # APIs without requiring MASTER to depend on the sibling-tree check kernel.
      VERIFICATION_STATUSES = %i[
        pass fail partial inconclusive error blocked timeout unavailable not_applicable
      ].freeze
      CHECK_OUTCOMES = {
        passed: :pass, pass: :pass,
        failed: :fail, fail: :fail,
        partial: :partial,
        inconclusive: :inconclusive,
        errored: :error, error: :error,
        blocked: :blocked,
        timeout: :timeout, timed_out: :timeout,
        unavailable: :unavailable,
        not_applicable: :not_applicable, skipped: :not_applicable
      }.freeze
      PROOF_OUTCOMES = { proven: :pass, failed: :fail, open: :inconclusive }.freeze

      VerificationResult = Data.define(
        :id, :subject, :verifier, :status, :scope_digest, :checked_count,
        :failure_count, :warning_count, :unchecked_count, :complete, :evidence_refs
      ) do
        def initialize(id:, subject:, verifier:, status:, scope: nil, scope_digest: nil,
                       checked_count: nil, failure_count: nil, warning_count: nil,
                       unchecked_count: nil, complete: nil, evidence_refs: [])
          id = Contract.token!(id, "verification id")
          verifier = Contract.token!(verifier, "verification verifier")
          subject = subject.to_s
          raise ArgumentError, "verification subject cannot be empty" if subject.strip.empty?
          raise ArgumentError, "verification subject is too long" if subject.bytesize > 1_024

          status = status.to_sym
          unless Contract::VERIFICATION_STATUSES.include?(status)
            raise ArgumentError, "unknown verification status: #{status}"
          end

          scope_digest ||= Digest::SHA256.hexdigest(scope.to_s) unless scope.nil?
          scope_digest = scope_digest.to_s.downcase unless scope_digest.nil?
          unless scope_digest.nil? || Contract::SHA256.match?(scope_digest)
            raise ArgumentError, "verification scope digest must be a SHA-256 hex digest"
          end

          counts = {
            checked_count: checked_count, failure_count: failure_count,
            warning_count: warning_count, unchecked_count: unchecked_count
          }.transform_values { |value| Contract.optional_count(value) }
          evidence_refs = Array(evidence_refs)
          unless evidence_refs.all? { |ref| ref.is_a?(Contract::EvidenceReference) }
            raise ArgumentError, "verification evidence must use typed EvidenceReference values"
          end

          complete = %i[pass fail error blocked timeout not_applicable].include?(status) if complete.nil?
          super(
            id:, subject: subject.freeze, verifier:, status:, scope_digest: scope_digest&.freeze,
            **counts, complete:, evidence_refs: evidence_refs.freeze
          )
        end

        def self.from_check_result(result, id:, subject:, verifier:, scope: nil)
          outcome = begin
            result.respond_to?(:outcome) ? result.outcome.to_sym : :inconclusive
          rescue StandardError
            :errored
          end
          status = Contract::CHECK_OUTCOMES.fetch(outcome, :inconclusive)
          conclusive = begin
            result.respond_to?(:conclusive?) ? result.conclusive? : true
          rescue StandardError
            false
          end
          status = :partial if status == :pass && conclusive == false

          new(
            id:, subject:, verifier:, status:, scope:,
            checked_count: read_count(result, :checks_ran),
            failure_count: read_collection_count(result, :failures),
            warning_count: read_collection_count(result, :warnings),
            unchecked_count: read_collection_count(result, :unchecked),
            complete: %i[pass fail error blocked timeout not_applicable].include?(status)
          )
        rescue StandardError
          new(id:, subject:, verifier:, status: :error, scope:, complete: false)
        end

        def self.from_proof(proof, id:, verifier:, scope: nil)
          source_status = proof.respond_to?(:status) ? proof.status.to_s.to_sym : :open
          status = Contract::PROOF_OUTCOMES.fetch(source_status, :inconclusive)
          subject = proof.respond_to?(:subject) ? proof.subject : nil
          # Claims may contain prompts or private output. The compact verification
          # receipt names the proof by ID instead of duplicating the claim text.
          subject = "proof:#{id}" if subject.to_s.empty?
          evidence = proof.respond_to?(:evidence) ? proof.evidence : nil
          refs = evidence.is_a?(EvidenceReference) ? [evidence] : []

          new(
            id:, subject:, verifier:, status:, scope:,
            evidence_refs: refs, complete: status != :inconclusive
          )
        end

        def pass? = status == :pass
        def fail? = status == :fail
        def conclusive? = complete == true && %i[pass fail].include?(status)

        def to_h
          {
            schema_version: 1, id:, subject:, verifier:, status:, scope_digest:,
            checked_count:, failure_count:, warning_count:, unchecked_count:,
            complete:, evidence_refs: evidence_refs.map(&:to_h)
          }.compact
        end

        def self.read_count(value, method)
          value.respond_to?(method) ? Contract.optional_count(value.public_send(method)) : nil
        rescue StandardError
          nil
        end
        private_class_method :read_count

        def self.read_collection_count(value, method)
          return nil unless value.respond_to?(method)

          collection = value.public_send(method)
          collection.respond_to?(:size) ? Contract.optional_count(collection.size) : nil
        rescue StandardError
          nil
        end
        private_class_method :read_collection_count
      end

      def optional_count(value)
        return nil if value.nil?

        count = Integer(value)
        count >= 0 ? count : nil
      rescue ArgumentError, TypeError
        nil
      end
      module_function :optional_count

      # Skills remain instructional content: declaring a capability never
      # grants it. This contract records version, provenance and validation state
      # so a future promotion gate can require evidence instead of trusting prose.
      SKILL_STATES = %i[unreviewed candidate approved deprecated blocked invalid].freeze
      SKILL_RISKS = %i[unknown low medium high critical].freeze
      SKILL_VERSION = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/
      REFERENCE = /\A[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,239}\z/
      SKILL_DECLARATION_KEYS = %w[schema_version version status risk required_capabilities laws fixtures provenance].freeze

      SkillContract = Data.define(
        :name, :revision, :source, :version, :status, :risk, :declared,
        :required_capabilities, :law_ids, :fixture_refs, :provenance, :errors
      ) do
        def self.from_declaration(name:, revision:, source:, declaration: nil)
          source_name = source.to_s
          errors = []
          data = declaration

          if data.nil?
            data = {}
          elsif !data.is_a?(Hash)
            errors << "declaration_not_a_mapping"
            data = {}
          end

          data = data.each_with_object({}) { |(key, value), normalized| normalized[key.to_s] = value }
          unknown = data.keys - Contract::SKILL_DECLARATION_KEYS
          errors << "unknown_fields" unless unknown.empty?
          schema_version = data.fetch("schema_version", 1)
          errors << "unsupported_schema_version" unless schema_version == 1

          version = data["version"]
          if !version.nil? && !(version.is_a?(String) && Contract::SKILL_VERSION.match?(version))
            errors << "invalid_version"
            version = nil
          end

          status = data.fetch("status", declaration.nil? ? "unreviewed" : "candidate").to_s.downcase.to_sym
          errors << "invalid_status" unless Contract::SKILL_STATES.include?(status)
          status = :invalid unless Contract::SKILL_STATES.include?(status)

          risk = data.fetch("risk", "unknown").to_s.downcase.to_sym
          errors << "invalid_risk" unless Contract::SKILL_RISKS.include?(risk)
          risk = :unknown unless Contract::SKILL_RISKS.include?(risk)

          required_capabilities = references(data["required_capabilities"], "required_capabilities", errors, /\A[a-zA-Z][a-zA-Z0-9_.:-]{0,79}\z/)
          law_ids = references(data["laws"], "laws", errors, Contract::TOKEN)
          fixture_refs = references(data["fixtures"], "fixtures", errors, Contract::REFERENCE)

          provenance = data["provenance"]
          if !provenance.nil? && !(provenance.is_a?(String) && provenance.bytesize <= 240)
            errors << "invalid_provenance"
            provenance = nil
          end

          status = :invalid if errors.any?
          new(
            name: Contract.token!(name.to_s.gsub(/[^a-zA-Z0-9._:-]/, "-")[0, 160], "skill name"),
            revision: checked_digest(revision),
            source: source_name.empty? ? "unknown" : source_name,
            version: version&.freeze,
            status:,
            risk:,
            declared: !declaration.nil?,
            required_capabilities: required_capabilities.freeze,
            law_ids: law_ids.freeze,
            fixture_refs: fixture_refs.freeze,
            provenance: provenance&.freeze,
            errors: errors.uniq.freeze
          )
        end

        def self.references(value, field, errors, pattern)
          return [] if value.nil?
          unless value.is_a?(Array) && value.length <= 64
            errors << "invalid_#{field}"
            return []
          end

          value.each_with_object([]) do |item, refs|
            unless item.is_a?(String) && pattern.match?(item)
              errors << "invalid_#{field}_entry"
              next
            end
            refs << item.freeze
          end.uniq
        end
        private_class_method :references

        def self.checked_digest(value)
          digest = value.to_s.downcase
          raise ArgumentError, "skill revision must be SHA-256 hex" unless Contract::SHA256.match?(digest)

          digest.freeze
        end
        private_class_method :checked_digest

        def declared? = declared == true

        def valid_declaration?
          declared? && !version.nil? && !fixture_refs.empty? &&
            !required_capabilities.empty? && !law_ids.empty? && errors.empty? &&
            !%i[blocked deprecated invalid].include?(status)
        end

        # Candidate means the contract is ready for operator review, not ready
        # for injection. The separate operator approval manifest pins its exact
        # content digest; changing one byte requires a new approval.
        def promotable? = status == :candidate && valid_declaration?

        # Compatibility is reserved for the pre-contract legacy population.
        # A declared skill always needs an external approval for this revision.
        def permitted_for_trigger? = !declared? && status == :unreviewed

        def to_h
          {
            schema_version: 1, name:, revision:, source:, version:, status:, risk:, declared:,
            required_capabilities:, law_ids:, fixture_refs:, provenance:, errors:
          }.compact
        end
      end

      # Privacy-safe effect identity for audit events. Arguments are deliberately
      # absent; callers can provide a digest of scope, not the scope itself.
      EffectEnvelope = Data.define(
        :effect_id, :turn, :verb, :capability, :operation, :parent_effect_id,
        :checkpoint_id, :run_id, :attempt_id, :mission_id, :scope_digest, :idempotency_key,
        :deadline_at
      ) do
        def self.build(effect:, turn:, effect_id:, operation: :perform, parent_effect_id: nil,
                       checkpoint_id: nil, run_id: nil, attempt_id: nil, mission_id: nil, scope: nil,
                       idempotency_key: nil, deadline_at: nil)
          unless effect.respond_to?(:verb) && effect.respond_to?(:capability)
            raise ArgumentError, "effect envelope requires a typed effect"
          end

          scope_digest = Digest::SHA256.hexdigest(scope.to_s) unless scope.nil? || scope.to_s.empty?
          new(
            effect_id:, turn:, verb: effect.verb, capability: effect.capability, operation:,
            parent_effect_id:, checkpoint_id:, run_id:, attempt_id:, mission_id:, scope_digest,
            idempotency_key:, deadline_at:
          )
        end

        def initialize(effect_id:, turn:, verb:, capability:, operation: :perform, parent_effect_id: nil,
                       checkpoint_id: nil, run_id: nil, attempt_id: nil, mission_id: nil, scope_digest: nil,
                       idempotency_key: nil, deadline_at: nil)
          effect_id = Contract.token!(effect_id, "effect id")
          turn = Integer(turn)
          raise ArgumentError, "effect turn must be non-negative" if turn.negative?

          verb = Contract.token!(verb, "effect verb").to_sym
          capability = Contract.token!(capability, "effect capability").to_sym
          operation = operation.to_s.to_sym
          unless Contract::EFFECT_OPERATIONS.include?(operation)
            raise ArgumentError, "unknown effect operation: #{operation}"
          end

          parent_effect_id = Contract.token!(parent_effect_id, "parent effect id") if parent_effect_id
          checkpoint_id = Contract.token!(checkpoint_id, "checkpoint id") if checkpoint_id
          run_id = Contract.token!(run_id, "run id") if run_id
          attempt_id = Contract.token!(attempt_id, "attempt id") if attempt_id
          mission_id = Contract.token!(mission_id, "mission id") if mission_id
          idempotency_key = Contract.token!(idempotency_key, "idempotency key") if idempotency_key

          scope_digest = scope_digest.to_s.downcase unless scope_digest.nil?
          unless scope_digest.nil? || Contract::SHA256.match?(scope_digest)
            raise ArgumentError, "scope digest must be a SHA-256 hex digest"
          end

          if deadline_at
            deadline_at = deadline_at.to_s
            Time.iso8601(deadline_at)
            deadline_at = deadline_at.freeze
          end

          super(
            effect_id:, turn:, verb:, capability:, operation:, parent_effect_id:,
            checkpoint_id:, run_id:, attempt_id:, mission_id:, scope_digest: scope_digest&.freeze,
            idempotency_key:, deadline_at:
          )
        rescue ArgumentError, TypeError, NoMethodError => e
          raise e if e.message.start_with?(
            "effect ", "unknown effect ", "parent effect ", "checkpoint ",
            "run id", "attempt id", "mission id", "idempotency key", "scope digest", "invalid effect envelope"
          )

          raise ArgumentError, "invalid effect envelope: #{e.message}"
        end

        def to_h
          {
            schema_version: 1, effect_id:, turn:, verb:, capability:, operation:,
            parent_effect_id:, checkpoint_id:, run_id:, attempt_id:, mission_id:, scope_digest:,
            idempotency_key:, deadline_at:
          }.compact
        end
      end
    end
  end
end
