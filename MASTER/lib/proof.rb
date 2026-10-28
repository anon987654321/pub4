# frozen_string_literal: true

require_relative "execution/contract"

module Master
  # Immutable claim/evidence envelope shared by scan, review and check adapters.
  # This is intentionally not Master::Core::Proof: that object owns Fold evidence
  # scoring, generations, writes and council state. Stage 1 only gives consumers
  # one stable shape without changing those semantics.
  Proof = Data.define(:claim, :law, :subject, :evidence, :source, :status, :metadata)

  # Reopened rather than given a Data.define block: a constant assigned in that block
  # lands on Master, where every module nested in it would read Master::SOURCES.
  class Proof
    SOURCES = { deterministic: 0, council: 1, llm: 2 }.freeze
    STATUSES = %i[proven failed open].freeze

    ENVELOPE = %i[evidence source status metadata].freeze

    # The claim and what it is about, then the envelope: evidence, source (:deterministic),
    # status (:open) and metadata.
    def self.build(claim:, law: nil, subject: nil, **envelope)
      source, status = checked_envelope(envelope)
      metadata = envelope.fetch(:metadata, {})

      new(
        claim: claim.to_s,
        law: law&.to_s,
        subject: subject&.to_s,
        evidence: freeze_value(envelope[:evidence]),
        source:,
        status:,
        metadata: metadata.is_a?(Hash) ? freeze_value(metadata) : {}.freeze,
      )
    end

    def self.checked_envelope(envelope)
      unknown = envelope.keys - ENVELOPE
      raise ArgumentError, "unknown keyword: #{unknown.first}" if unknown.any?

      source = envelope.fetch(:source, :deterministic).to_sym
      status = envelope.fetch(:status, :open).to_sym
      raise ArgumentError, "unknown proof source: #{source}" unless SOURCES.key?(source)
      raise ArgumentError, "unknown proof status: #{status}" unless STATUSES.include?(status)

      [source, status]
    end

    def self.source_rank(source) = SOURCES.fetch(source.to_sym)

    def self.freeze_value(value)
      case value
      when Hash
        value.each { |key, item| freeze_value(key); freeze_value(item) }.freeze
      when Array
        value.each { |item| freeze_value(item) }.freeze
      when String
        value.dup.freeze
      else
        value.freeze
      end
    end
    private_class_method :freeze_value

    def proven? = status == :proven
    def failed? = status == :failed
    def open? = status == :open

    def to_h
      {
        claim:,
        law:,
        subject:,
        evidence:,
        source:,
        status:,
        metadata:,
      }.compact
    end

    # Map the claim's existing proof state into the shared execution outcome
    # vocabulary. The evidence payload itself is not copied into the result.
    def to_verification(id:, verifier: "master-proof", scope: nil)
      Master::Execution::Contract::VerificationResult.from_proof(
        self, id:, verifier:, scope:
      )
    end
  end
end
