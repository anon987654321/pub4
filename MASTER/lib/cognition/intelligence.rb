# frozen_string_literal: true

require "digest"
require "json"

module Master
  module Cognition
    # Small, executable habits for reasoning under uncertainty.
    # This is a protocol, not a claim that the runtime has human-like thought.
    module Intelligence
      EVIDENCE_STATES = %i[observed inferred verified contradicted uncertain obsolete].freeze
      SCALE_LAYERS = %i[local subsystem tree repository production human].freeze
      SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
      POSTURES = %i[preserve explore verify improve].freeze

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

      # Rank opportunities by consequence, not by how loud or numerous they are.
      # The signals are intentionally generic so scanners, councils and future model
      # judges can share one vocabulary without growing another scoring subsystem.
      def leverage_score(item)
        row = item.respond_to?(:to_h) ? item.to_h : item
        row = row.is_a?(Hash) ? row : {}
        blast = fetch_hash(row, :blast_radius, :impact_radius)
        files = signal(blast, :files_touched, :files, fallback: signal(row, :files_touched, :files))
        consumers = signal(blast, :consumers, :dependents, :callers, fallback: signal(row, :consumers, :dependents, :callers))
        boundaries = signal(blast, :boundaries, :trees, fallback: signal(row, :boundaries, :trees))
        rules = signal(blast, :rules, :contracts, fallback: signal(row, :rules, :contracts))
        deletions = signal(blast, :deletions, :removed, fallback: signal(row, :deletions, :removed))
        severity = SEVERITY_RANK.fetch((row[:severity] || row["severity"] || :warning).to_sym, 1)
        (files * 2) + (consumers * 3) + (boundaries * 4) + (rules * 2) + (deletions * 2) + severity
      end

      def rank_by_leverage(items)
        rows = Array(items)
        rows.map.with_index { |item, index| [item, index] }
            .sort_by { |item, index| [-leverage_score(item), -severity_score(item), index] }
            .map(&:first)
      end

      def judgment(item)
        confidence = signal(item, :confidence, fallback: 0.5).to_f.clamp(0.0, 1.0)
        uncertainty = uncertainty_score(item)
        {
          leverage: leverage_score(item),
          confidence: confidence.round(4),
          uncertainty: uncertainty.round(4),
          posture: posture_for(item, uncertainty:),
          scale: scale_for(item),
        }.freeze
      end

      # Allocate a bounded attention budget without discarding the least certain
      # candidate merely because it has low measured leverage.
      def attention_budget(items, slots: 7)
        rows = Array(items)
        limit = slots.to_i.clamp(0, rows.size)
        ranked = rank_by_leverage(rows)
        selected = ranked.first(limit)
        preserved_uncertainty = ranked
          .reject { |item| selected.include?(item) }
          .sort_by { |item| [-uncertainty_score(item), -leverage_score(item)] }
          .find { |item| uncertainty_score(item) >= 0.65 }

        selected << preserved_uncertainty if preserved_uncertainty
        {
          candidates: rows.size,
          selected: selected,
          deferred: ranked.reject { |item| selected.include?(item) },
          preserved_uncertainty: preserved_uncertainty,
        }.freeze
      end

      def uncertainty_score(item)
        row = item.respond_to?(:to_h) ? item.to_h : item
        status = (row[:status] || row["status"] || :uncertain).to_sym
        confidence = signal(row, :confidence, fallback: 0.5).to_f.clamp(0.0, 1.0)
        base = 1.0 - confidence
        base += 0.25 if %i[uncertain contradicted obsolete].include?(status)
        base += 0.15 if row[:requires_validation] || row["requires_validation"]
        base.clamp(0.0, 1.0)
      end

      def posture_for(item, uncertainty: uncertainty_score(item))
        row = item.respond_to?(:to_h) ? item.to_h : item
        return :preserve if uncertainty >= 0.65
        return :explore if reversible?(row)
        return :verify if uncertainty >= 0.2

        :improve
      end

      # Conceptual equality deliberately compares declared purpose and boundaries,
      # not names. It is a compact second-order key: a later model can populate the
      # fields from source evidence, while deterministic code can compare the result.
      def conceptual_signature(value)
        row = value.is_a?(Hash) ? value : { purpose: value }
        canonical = %i[purpose intent inputs outputs side_effects invariants boundary]
                    .each_with_object({}) do |key, out|
          source = row[key] || row[key.to_s]
          out[key] = canonicalize(source) unless source.nil?
        end
        Digest::SHA256.hexdigest(JSON.generate(canonical))[0, 24]
      end

      def conceptually_equivalent?(left, right)
        conceptual_signature(left) == conceptual_signature(right)
      end

      def decision_frame(observation:, hypothesis:, falsifier:, measurement:, source:,
                         selected: nil, alternatives: [], status: :uncertain, cause: nil, effect: nil)
        frame = claim_frame(
          claim: hypothesis,
          observation:,
          inference: selected || hypothesis,
          falsifier:,
          measurement:,
          source:,
          status:,
        )
        frame.merge(
          "alternatives" => Array(alternatives).map(&:to_s).first(7),
          "selected" => selected.to_s,
          "causal" => { "cause" => cause.to_s, "effect" => effect.to_s }.reject { |_, v| v.empty? },
          "teaching" => {
            "local" => observation.to_s,
            "boundary" => source.to_s,
            "next_step" => (selected.to_s.empty? ? hypothesis.to_s : selected.to_s),
          },
        ).freeze
      end

      # Keep the two hypotheses explicit and name the smallest observation that
      # could separate them. A counterfactual frame is not itself a verdict.
      def counterfactual_frame(hypothesis:, alternative:, boundary:, measurement:, expected_difference:)
        ready = [hypothesis, alternative, boundary, measurement, expected_difference].all? do |value|
          !value.to_s.strip.empty?
        end
        {
          hypothesis: hypothesis.to_s,
          alternative: alternative.to_s,
          boundary: boundary.to_s,
          measurement: measurement.to_s,
          expected_difference: expected_difference.to_s,
          ready:,
        }.freeze
      end

      # Unfinished work needs positive value evidence before it is called fertile,
      # and inactivity alone is never enough to call it dead.
      def fertility(consumers: 0, operator_owned: false, novelty: 0.0, unused_days: 0, confidence: 0.5)
        consumers = consumers.to_i
        novelty = novelty.to_f.clamp(0.0, 1.0)
        unused_days = unused_days.to_f
        confidence = confidence.to_f.clamp(0.0, 1.0)

        value_evidence = []
        value_evidence << :consumers if consumers.positive?
        value_evidence << :operator_owned if operator_owned
        value_evidence << :novelty if novelty >= 0.7

        dead_evidence = []
        dead_evidence << :long_unused if unused_days >= 180
        dead_evidence << :no_consumers if consumers.zero?
        dead_evidence << :low_novelty if novelty < 0.2
        dead_evidence << :low_confidence if confidence < 0.4

        posture =
          if value_evidence.size >= 2
            :fertile
          elsif dead_evidence.size >= 3 && confidence >= 0.8
            :dead
          else
            :investigate
          end

        {
          posture:,
          value_evidence:,
          dead_evidence:,
          requires_measurement: posture == :investigate,
        }.freeze
      end

      def creative_frame(identity:, mutable:, invariants:, axis: :one_at_a_time)
        {
          identity: canonicalize(identity),
          mutable: Array(mutable).map(&:to_s).first(12),
          invariants: Array(invariants).map(&:to_s).first(12),
          axis: axis.to_sym,
          posture: :preserve,
        }.freeze
      end

      def preference_frame(domain:, preference:, evidence:, source:, avoid: nil, confidence: 0.5)
        {
          domain: domain.to_s,
          preference: preference.to_s.strip,
          avoid: avoid.to_s.strip,
          evidence: evidence.to_s.strip,
          source: source.to_s,
          confidence: confidence.to_f.clamp(0.0, 1.0).round(4),
        }.freeze
      end

      def orientation_contract
        [
          "judgment: rank changes by causal leverage, not finding volume",
          "scales: reason local → subsystem → tree → repository → production → human",
          "equivalence: compare purpose, inputs, outputs, side effects and boundaries, not names",
          "uncertainty: preserve uncertain or contradicted work until a falsifier or measurement resolves it",
          "creative work: preserve identity and invariants; mutate one declared axis at a time",
          "unfinished work: distinguish fertile uncertainty from proven deadness before deleting it",
          "teaching: explain the local decision first, then the boundary and consequence it changes",
        ].join("
")
      end

      def causality_contract
        "causality: cause → effect → evidence; a broken handoff is a finding, not permission to guess"
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

      # Collapse identical positions, retain their provenance, and refuse to turn
      # a split panel into a majority vote. A disagreement stays unresolved until
      # a measurement can separate the competing claims.
      def synthesize_judgments(feedback)
        entries = Array(feedback).filter_map do |entry|
          row = entry.respond_to?(:to_h) ? entry.to_h : entry
          next unless row.is_a?(Hash)

          claim = row[:claim] || row["claim"] || row[:feedback] || row["feedback"]
          claim = claim.to_s.strip
          next if claim.empty?

          {
            persona: (row[:persona] || row["persona"]).to_s,
            claim:,
            key: claim.downcase.gsub(/\s+/, " "),
            confidence: signal(row, :confidence, fallback: 0.5).to_f.clamp(0.0, 1.0),
            falsifier: (row[:falsifier] || row["falsifier"]).to_s.strip,
          }
        end

        groups = entries.group_by { |entry| entry[:key] }
        positions = groups.values.map do |rows|
          {
            claim: rows.first[:claim],
            support: rows.size,
            confidence: (rows.sum { |row| row[:confidence] } / rows.size).round(4),
            personas: rows.filter_map { |row| row[:persona].empty? ? nil : row[:persona] }.uniq,
            falsifiers: rows.filter_map { |row| row[:falsifier].empty? ? nil : row[:falsifier] }.uniq,
          }.freeze
        end.sort_by { |position| [-position[:support], -position[:confidence], position[:claim]] }

        disagreement = positions.size > 1
        requires_measurement = disagreement ||
          positions.any? { |position| position[:falsifiers].empty? || position[:confidence] < 0.6 }
        leading = positions.size == 1 ? positions.first[:claim] : nil

        {
          positions: positions,
          disagreement:,
          requires_measurement:,
          leading:,
        }.freeze
      end

      def signal(row, *keys, fallback: 0)
        row = row.to_h if row.respond_to?(:to_h) && !row.is_a?(Hash)
        return fallback unless row.is_a?(Hash)
        keys.each do |key|
          value = row[key] || row[key.to_s]
          return value.to_f if value.is_a?(Numeric)
        end
        fallback
      end

      def fetch_hash(row, *keys)
        keys.each do |key|
          value = row[key] || row[key.to_s]
          return value if value.is_a?(Hash)
        end
        {}
      end

      def severity_score(item)
        row = item.respond_to?(:to_h) ? item.to_h : item
        SEVERITY_RANK.fetch((row[:severity] || row["severity"] || :warning).to_sym, 1)
      end

      def reversible?(row)
        value = row[:reversibility] || row["reversibility"] || row[:reversible] || row["reversible"]
        %w[reversible guarded].include?(value.to_s.downcase) || value == true
      end

      def scale_for(item)
        row = item.respond_to?(:to_h) ? item.to_h : item
        explicit = row[:scale] || row["scale"]
        return explicit.to_sym if explicit && SCALE_LAYERS.include?(explicit.to_sym)
        impact = leverage_score(row)
        return :human if impact >= 50
        return :production if impact >= 35
        return :repository if impact >= 22
        return :tree if impact >= 12
        return :subsystem if impact >= 5

        :local
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.map(&:to_s).sort.each_with_object({}) do |key, out|
            out[key] = canonicalize(value[key] || value[key.to_sym])
          end
        when Array
          value.map { |item| canonicalize(item) }.sort_by(&:to_s)
        when Symbol then value.to_s
        when String then value.strip.gsub(/\s+/, " ").downcase
        else value
        end
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
          leverage: prioritize changes whose causal reach crosses consumers, boundaries, and contracts
          scales: local → subsystem → tree → repository → production → human
          equivalence: compare declared purpose, inputs, outputs, side effects and invariants, not names
          creativity: preserve identity and invariants while changing one axis at a time
          teaching: explain the decision at its current scale before expanding outward
          action: prefer the smallest change that can test the hypothesis without losing the best measured state
        TEXT
      end
    end
  end
end
