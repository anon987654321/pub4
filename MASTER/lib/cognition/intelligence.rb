# frozen_string_literal: true

require "digest"
require "json"

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
        ).freeze
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

      # Attention is finite. Select the highest-leverage candidates first,
      # but keep an uncertain candidate visible when it would otherwise disappear.
      def attention_budget(items, slots: 5, token_budget: 2_000)
        rows = rank_by_leverage(items)
        chosen = rows.first(slots.to_i)
        uncertain = rows.drop(slots.to_i).select { |item| uncertainty_score(item) >= 0.65 }.first
        chosen << uncertain if uncertain && !chosen.include?(uncertain)
        {
          slots: slots.to_i,
          token_budget: token_budget.to_i,
          candidates: rows.size,
          selected: chosen,
          deferred: rows - chosen,
          preserved_uncertainty: uncertain,
        }.freeze
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
          "teaching" => teaching_frame(
            local: observation,
            boundary: source,
            consequence: hypothesis,
            next_step: selected || measurement,
          ),
          "counterfactual" => counterfactual_frame(
            hypothesis: hypothesis,
            alternative: Array(alternatives).first || "preserve current behavior",
            boundary: source,
            measurement: measurement,
            expected_difference: "the next measurement should distinguish the chosen path from the preserved path",
          ),
        ).freeze
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

      def orientation_contract
        [
          "judgment: rank changes by causal leverage, not finding volume",
          "attention: keep reasoning bounded and preserve high-uncertainty candidates",
          "scales: reason local → subsystem → tree → repository → production → human",
          "equivalence: compare purpose, inputs, outputs, side effects and boundaries, not names",
          "uncertainty: preserve uncertain or contradicted work until a falsifier or measurement resolves it",
          "creative work: preserve identity and invariants; mutate one declared axis at a time",
          "unfinished work: distinguish fertile uncertainty from proven deadness before deleting it",
          "teaching: explain the local decision first, then the boundary and consequence it changes",
        ].join("\n")
      end

      def counterfactual_frame(hypothesis:, alternative:, boundary:, measurement:, expected_difference:)
        {
          hypothesis: hypothesis.to_s,
          alternative: alternative.to_s,
          boundary: boundary.to_s,
          measurement: measurement.to_s,
          expected_difference: expected_difference.to_s,
          ready: [hypothesis, alternative, boundary, measurement, expected_difference].all? { |value| !value.to_s.strip.empty? },
        }.freeze
      end

      # Synthesize panel opinions without majority-vote semantics. A position leads
      # only when weighted evidence separates it from the runner-up; disagreement
      # stays explicit and always carries a next measurement.
      def synthesize_judgments(reports)
        rows = Array(reports).filter_map { |report| judgment_row(report) }
        return { count: 0, positions: [], leading: nil, disagreement: false, requires_measurement: true }.freeze if rows.empty?

        groups = rows.group_by { |row| row[:signature] }
        positions = groups.map do |signature, group|
          score = group.sum { |row| row[:confidence] * (1.0 - row[:uncertainty]) }
          {
            signature:,
            position: group.first[:position],
            score: score.round(4),
            voices: group.map { |row| row[:source] }.uniq,
            evidence: group.map { |row| row[:evidence] }.reject(&:empty?).uniq.first(6),
            falsifiers: group.map { |row| row[:falsifier] }.reject(&:empty?).uniq.first(6),
          }
        end.sort_by { |row| -row[:score] }
        top = positions[0]
        runner = positions[1]
        gap = runner ? top[:score] - runner[:score] : top[:score]
        {
          count: rows.size,
          positions: positions.first(7),
          leading: positions.size == 1 || gap >= 0.15 ? top : nil,
          disagreement: positions.size > 1,
          requires_measurement: positions.size > 1 || rows.any? { |row| row[:uncertainty] >= 0.35 },
          next_measurement: rows.map { |row| row[:falsifier] }.reject(&:empty?).first || "run the smallest deterministic test that separates the leading positions",
        }.freeze
      end

      def preference_frame(domain:, preference:, evidence:, source:, avoid: nil, confidence: 0.8)
        {
          domain: domain.to_s,
          preference: preference.to_s,
          avoid: avoid.to_s,
          evidence: evidence.to_s,
          source: source.to_s,
          confidence: confidence.to_f.clamp(0.0, 1.0).round(4),
        }.freeze
      end

      # Fertility is a preservation signal, never a deletion authority. It asks
      # whether there is concrete value evidence before an unfinished thing is
      # classified as dead; otherwise the result remains investigate.
      def fertility(item)
        row = item.respond_to?(:to_h) ? item.to_h : item
        row = {} unless row.is_a?(Hash)
        consumers = signal(row, :consumers, :consumer_count, :dependents, :callers)
        unused_days = signal(row, :unused_days, :last_used_days, fallback: 0)
        novelty = signal(row, :novelty, fallback: 0).to_f.clamp(0.0, 1.0)
        value = []
        dead = []
        value << :consumers if consumers.positive?
        value << :operator_owned if row[:operator_owned] || row["operator_owned"]
        value << :novelty if novelty >= 0.5
        value << :recent_use if unused_days < 90
        dead << :no_consumers if consumers.zero?
        dead << :long_unused if unused_days >= 180
        dead << :duplicate if row[:duplicate] || row["duplicate"]
        dead << :explicit_dead if row[:explicit_dead] || row["explicit_dead"]
        uncertainty = uncertainty_score(row)
        posture = if dead.length >= 3 && uncertainty < 0.2
                     :dead
                   elsif value.length >= 2
                     :fertile
                   else
                     :investigate
                   end
        { posture:, value_evidence: value, dead_evidence: dead, uncertainty: uncertainty.round(4) }.freeze
      end

      def teaching_frame(local:, boundary:, consequence:, next_step:)
        {
          local: local.to_s,
          boundary: boundary.to_s,
          consequence: consequence.to_s,
          next_step: next_step.to_s,
        }.freeze
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

      def judgment_row(report)
        row = report.respond_to?(:to_h) ? report.to_h : { claim: report.to_s, feedback: report.to_s }
        position = row[:position] || row["position"] || row[:recommendation] || row["recommendation"] ||
                   row[:claim] || row["claim"] || row[:feedback] || row["feedback"]
        position = position.to_s.strip
        return if position.empty?

        evidence = (row[:evidence] || row["evidence"] || "").to_s.strip
        falsifier = (row[:falsifier] || row["falsifier"] || "").to_s.strip
        confidence = signal(row, :confidence, fallback: 0.5).to_f.clamp(0.0, 1.0)
        status = (row[:status] || row["status"] || :uncertain).to_sym
        uncertainty = uncertainty_score(row)
        {
          source: (row[:model] || row["model"] || row[:persona] || row["persona"] || "anonymous").to_s,
          position: position,
          signature: if row.key?(:purpose) || row.key?("purpose") || row.key?(:intent) || row.key?("intent")
                       conceptual_signature(row)
                     else
                       canonicalize(position)
                     end,
          confidence:,
          uncertainty:,
          evidence:,
          falsifier:,
          status:,
        }
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
