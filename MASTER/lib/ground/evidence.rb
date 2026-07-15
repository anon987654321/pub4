# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Ground
    # Enforces source-typed evidence requirements for governed actions.
    class Evidence
      DEFAULT_REL = "data/patterns.yml"
      EXIT_CODE_TYPES = %w[test_pass static_analysis type_check].freeze

      def self.load(root: Master::ROOT, event_bus: nil)
        config = (Master.load_yaml(File.join(root, DEFAULT_REL)) || {})["evidence"] || {}
        new(config, root:, event_bus:)
      end

      attr_reader :schema

      def initialize(config, root:, event_bus: nil)
        @root = File.expand_path(root)
        @bus = event_bus
        @config = config.is_a?(Hash) ? config : {}
        @schema = @config.fetch("schema", 0)
        @source_config = @config.fetch("sources", {})
        @required_actions = Array(@config["required_for"]).map(&:to_s).freeze
        @combine = @config.fetch("combine", {})
      end

      def required?(action) = @required_actions.include?(action.to_s)

      def verify(action:, sources:)
        classified = classify(Array(sources))
        trust = total_trust(classified)
        result = evidence_result(action.to_s, classified, trust)
        audit(action.to_s, classified, trust, result)
        result
      end

      def trust_for(source_type)
        value = @source_config.dig(source_type.to_s, "trust")
        value.is_a?(Numeric) && value.between?(0.0, 1.0) ? value.to_f : 0.0
      end

      private

      def evidence_result(action, sources, trust)
        return Result.ok(trust:, sources:) unless required?(action)

        error = required_evidence_error(action, sources, trust)
        error || Result.ok(trust:, sources:)
      end

      def required_evidence_error(action, sources, trust)
        verified = sources.select { |source| source[:verified] }
        minimum = @combine.fetch("min_total_trust", 0.75).to_f
        missing_sources_error(action, sources) ||
          unverified_sources_error(action, verified) ||
          trust_threshold_error(action, trust, minimum) ||
          strong_source_error(action, verified, minimum)
      end

      def classify(sources)
        classified = sources.filter_map do |source|
          next unless source.respond_to?(:[])

          type = value(source, :type).to_s
          next if type.empty?

          verified, reason = verified_source(type, source)
          { type:, trust: verified ? trust_for(type) : 0.0, verified:, reason: }
        end
        classified.uniq
      end

      def verified_source(type, source)
        return [false, "unknown source type"] unless @source_config.key?(type)

        verifier, reason = verifier_for(type)
        # Guard against undefined verifier methods
        unless respond_to?(verifier, true)
          return [false, "verifier #{verifier} not implemented"]
        end
        [send(verifier, source), reason]
      end

      def verifier_for(type)
        return [:exit_code_success?, "exit code"] if EXIT_CODE_TYPES.include?(type)

        {
          "scan_clean" => [:scan_clean?, "scan result"],
          "doc_link" => [:document_verified?, "document response"],
          "git_blame" => [:attributed?, "git attribution"],
          "user_assertion" => [:confirmed?, "operator confirmation"],
          "llm_consensus" => [:consensus?, "provider consensus"],
        }.fetch(type, [:explicitly_verified?, "explicit verifier"])
      end

      def exit_code_success?(source) = !value(source, :exit_code).nil? && value(source, :exit_code).to_i.zero?
      def scan_clean?(source) = source_key?(source, :violations) && Array(value(source, :violations)).empty?
      def document_verified?(source) = value(source, :status).to_i == 200 && value(source, :claim_present) == true
      def attributed?(source) = value(source, :attributed) == true
      def confirmed?(source) = value(source, :confirmed) == true
      def consensus?(source)
        providers = Array(value(source, :providers)).map(&:to_s)
        providers.uniq.size >= 2
      end

      # Fallback verifier for unknown source types — requires explicit :verified key
      def explicitly_verified?(source) = value(source, :verified) == true
      def explicitly_verified?(source) = value(source, :verified) == true

      def total_trust(sources)
        weights = sources.select { |source| source[:verified] }.map { |source| source[:trust] }
        return 0.0 if weights.empty?

        1.0 - weights.inject(1.0) { |product, weight| product * (1.0 - weight) }
      end

      def audit(action, sources, trust, result)
        payload = {
          at: Time.now.utc.iso8601,
          action:,
          trust: trust.round(6),
          accepted: result.ok?,
          sources: sources.map { |source| source.slice(:type, :trust, :verified, :reason) },
        }
        @bus&.publish("evidence:verified", payload)
        append_audit(payload)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "evidence.audit", event_bus: @bus)
      end

      def append_audit(payload)
        relative = @config.dig("audit", "log_to")
        return if relative.to_s.empty?

        path = File.expand_path(relative, @root)
        return unless path.start_with?(@root + File::SEPARATOR)

        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a", 0o600) { |file| file.puts(JSON.generate(payload)) }
      end

      def value(source, key) = source[key] || source[key.to_s]

      def source_key?(source, key)
        source.respond_to?(:key?) && (source.key?(key) || source.key?(key.to_s))
      end
      def validation_error(message) = Result.err(message, category: :validation)
      def strong_source_required? = @combine["require_at_least_one_strong"] == true

      def missing_sources_error(action, sources)
        validation_error("evidence required for #{action}, none supplied") if sources.empty?
      end

      def unverified_sources_error(action, verified)
        validation_error("evidence required for #{action}, no source verified") if verified.empty?
      end

      def trust_threshold_error(action, trust, minimum)
        validation_error("evidence trust #{trust.round(2)} < #{minimum} for #{action}") if trust < minimum
      end

      def strong_source_error(action, verified, minimum)
        return unless strong_source_required?
        return if verified.any? { |source| source[:trust] >= minimum }

        validation_error("evidence for #{action} requires one source with trust >= #{minimum}")
      end
    end
  end
end
