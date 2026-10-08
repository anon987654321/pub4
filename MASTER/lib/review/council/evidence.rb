# frozen_string_literal: true

module Master
  module Review
    module Council
      # Evidence envelope shared by every tribunal domain.
      #
      # Probes remain domain-specific. This object records what a probe actually
      # observed and preserves INCONCLUSIVE as a first-class outcome.
      Evidence = Data.define(
        :artifact,
        :domain,
        :status,
        :observations,
        :measurements,
        :structure,
        :anchors,
        :provenance,
      ) do
        STATUSES = %i[observed inconclusive failed].freeze

        def initialize(
          artifact:,
          domain:,
          status: :observed,
          observations: [],
          measurements: {},
          structure: {},
          anchors: [],
          provenance: {}
        )
          status = status.to_sym
          raise ArgumentError, "unknown evidence status: #{status}" unless STATUSES.include?(status)

          super(
            artifact: artifact.to_s,
            domain: domain.to_sym,
            status:,
            observations: Array(observations).map(&:to_s).freeze,
            measurements: measurements.is_a?(Hash) ? measurements.freeze : {},
            structure: structure.is_a?(Hash) ? structure.freeze : {},
            anchors: Array(anchors).map(&:to_s).freeze,
            provenance: provenance.is_a?(Hash) ? provenance.freeze : {},
          )
        end

        def actionable?
          status == :observed && anchors.any? && observations.any?
        end

        def inconclusive?
          status == :inconclusive
        end

        def to_h
          {
            artifact:,
            domain:,
            status:,
            observations:,
            measurements:,
            structure:,
            anchors:,
            provenance:,
          }
        end

        def prompt
          [
            "EVIDENCE",
            "artifact: #{artifact}",
            "domain: #{domain}",
            "status: #{status}",
            "observations:",
            observations.map { |value| "- #{value}" },
            "measurements:",
            measurements.map { |key, value| "- #{key}: #{value}" },
            "structure:",
            structure.map { |key, value| "- #{key}: #{value}" },
            "anchors:",
            anchors.map { |anchor| "- #{anchor}" },
            "provenance:",
            provenance.map { |key, value| "- #{key}: #{value}" },
          ].flatten.join("\n")
        end
      end
    end
  end
end
