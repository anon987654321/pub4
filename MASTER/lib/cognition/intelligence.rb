# frozen_string_literal: true

module Master
  module Cognition
    # Small, executable habits for reasoning under uncertainty.
    # This is a protocol, not a claim that the runtime has human-like thought.
    module Intelligence
      EVIDENCE_STATES = %i[observed inferred verified contradicted uncertain obsolete].freeze
      ROUTES = {
        conversation: :talk,
        repository: :inspect_source,
        web_current: :search_current,
        deep_research: :research,
        browser: :interact_browser,
        device: :inspect_device,
        unknown: :ask_for_evidence,
      }.freeze

      module_function

      def route(text)
        mode = Ground::EvidenceRouter.classify(text)
        { mode:, action: ROUTES.fetch(mode), web_required: Ground::EvidenceRouter.web_required?(mode) }
      end

      def claim_frame(claim:, observation:, inference:, falsifier:, measurement:, source:, status: :uncertain)
        status = status.to_sym
        raise ArgumentError, "unknown evidence status: #{status}" unless EVIDENCE_STATES.include?(status)

        {
          claim: claim.to_s,
          observation: observation.to_s,
          inference: inference.to_s,
          falsifier: falsifier.to_s,
          measurement: measurement.to_s,
          source: source.to_s,
          status:,
          ready_to_verify: !claim.to_s.empty? && !observation.to_s.empty? &&
            !falsifier.to_s.empty? && !measurement.to_s.empty?,
        }.freeze
      end

      def causal_trace(steps)
        rows = Array(steps).map do |step|
          {
            cause: step.fetch(:cause).to_s,
            effect: step.fetch(:effect).to_s,
            evidence: step.fetch(:evidence).to_s,
          }
        end
        gaps = rows.each_cons(2).filter_map do |left, right|
          next if left[:effect] == right[:cause]

          { from: left[:effect], to: right[:cause] }
        end
        { steps: rows, complete: rows.any? && gaps.empty?, gaps: }.freeze
      rescue KeyError => e
        { steps: [], complete: false, gaps: [{ missing: e.key.to_s }] }.freeze
      end

      # Compression removes repetition without deleting provenance. Identical
      # semantic labels collapse to one row and retain every source reference.
      def compress(items, max: 7)
        grouped = Hash.new { |hash, key| hash[key] = [] }
        Array(items).each do |item|
          row = item.is_a?(Hash) ? item : { label: item }
          label = row[:label] || row["label"] || row[:name] || row["name"]
          next if label.to_s.strip.empty?

          grouped[label.to_s] << row
        end
        grouped.map do |label, rows|
          sources = rows.filter_map { |row| row[:source] || row["source"] }.uniq
          { label:, count: rows.size, sources: }
        end.sort_by { |row| [-row[:count], row[:label]] }.first(max.to_i).freeze
      end

      def falsification_questions(claim)
        value = claim.to_s.strip
        [
          "What observation would make this claim false?",
          "What existing behavior would regress if this claim is wrong?",
          "What smallest measurement could distinguish this claim from its opposite?",
          "What source or test could directly contradict the claim?",
          "What changed recently that could make old evidence obsolete?",
        ].map { |question| "#{question} Claim: #{value}" }
      end

      def reasoning_contract
        <<~TEXT.strip
          intelligence contract:
          evidence: separate observation from inference; mark uncertainty instead of filling gaps
          falsification: every material claim names a counterexample and a smallest measurement
          causality: trace cause → effect across boundaries; flag broken links before mutation
          compression: remove semantic repetition while preserving provenance and source references
          routing: choose evidence source before choosing an answer; stale or unavailable evidence is not proof
          humility: contradicted and obsolete evidence stays visible until superseded by newer evidence
          action: prefer the smallest change that can test the hypothesis without losing the best measured state
        TEXT
      end
    end
  end
end
