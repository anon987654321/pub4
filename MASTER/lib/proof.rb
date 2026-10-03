# frozen_string_literal: true

module Master
  # Immutable claim/evidence envelope shared by scan, review and gate adapters.
  # This is intentionally not Master::Core::Proof: that object owns Fold evidence
  # scoring, generations, writes and council state. Stage 1 only gives consumers
  # one stable shape without changing those semantics.
  Proof = Data.define(
    :claim, :rule, :subject, :evidence, :source, :status, :metadata
  ) do
    SOURCES = { deterministic: 0, council: 1, llm: 2 }.freeze
    STATUSES = %i[proven failed open].freeze

    def self.build(claim:, rule: nil, subject: nil, evidence: nil, source: :deterministic,
                   status: :open, metadata: {})
      source = source.to_sym
      status = status.to_sym
      raise ArgumentError, "unknown proof source: #{source}" unless SOURCES.key?(source)
      raise ArgumentError, "unknown proof status: #{status}" unless STATUSES.include?(status)

      new(
        claim: claim.to_s,
        rule: rule&.to_s,
        subject: subject&.to_s,
        evidence: freeze_value(evidence),
        source: source,
        status: status,
        metadata: metadata.is_a?(Hash) ? freeze_value(metadata) : {}.freeze,
      )
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
        rule:,
        subject:,
        evidence:,
        source:,
        status:,
        metadata:,
      }.compact
    end
  end
end
