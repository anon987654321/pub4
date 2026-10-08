# frozen_string_literal: true

require "digest"
require "json"
require_relative "../cognition/intelligence"

module Master
  module Fix
    # Executable remnants of the historical MASTER convergence contract.
    #
    # The old master.json/master.yml files spread these ideas across hundreds
    # of lines. The runtime needs the semantics, not another constitution-shaped
    # document.
    class ConvergenceDiscipline
      UNMEASURED_SCORE = 1_000_000_000

      DEFAULT_HYGIENE_PROMPT = <<~TEXT.strip
        fix hygiene contract (enforce on every mutation in this /fix pass):
        
        1. numeric ranks: never .to_i/.to_int on values that may be Infinity/NaN; use finite sentinels
        2. extract-then-match: if you strip a body from source, the next pattern must match that body
        3. regex fixtures: every new extractor includes a unit fixture of the real surface form
        4. bare-invoke / defaults: one dispatch path; update tests and comments in the same change
        5. source pins: assert stable public names, never match against whole multi-MB files
        6. event topics: literal string publishers; no stale aliases (see data/event_topics.yml)
        7. dual paths: after early return/exit, delete or share one function with the later twin
        8. gates: label SKIPPED vs FAILED vs crash
        9. limits/guidance: new limits keys need a reader, or stay under guidance: only
        
        When proposing a patch, name which checklist id (A–G) you satisfied or waive with one line.
        Deterministic census beats LLM invention for topic lists and call graphs.
      TEXT

      DEFAULTS = {
        "clean_runs_required" => 2,
        "diminishing_delta" => 0.001,
        "diminishing_cycles" => 3,
        "working_memory_items" => 7,
        "context_switches_per_round" => 3,
        "decision_choices" => 7,
        "alternatives_min" => 5,
        "alternatives_max" => 20,
        "observation_to_mutation_ratio" => 10,
      }.freeze

      def initialize(root:, bus: nil)
        @root = File.expand_path(root)
        @bus = bus
        @history = []
        @best_state = nil
        @baseline = nil
        @reasoning_memory = nil
      end

      attr_reader :best_state, :history

      def begin_run(files)
        @baseline = snapshot(files)
        @best_state = state_for(0, UNMEASURED_SCORE, @baseline)
        @history.clear
        @history = []
        emit("fix_loop:convergence_baseline", files: @baseline.size, digest: digest(@baseline))
        @baseline
      end

      def observe(pass:, findings:, files:, progressed:)
        current = snapshot(files)
        state = state_for(pass, Array(findings).size, current)
        @history << state.merge(progressed:)
        @best_state = state if @best_state.nil? || state[:score] < @best_state[:score]

        ranked = Master::Cognition::Intelligence.rank_by_leverage(findings)
        top = ranked.first
        @bus&.publish(
          "fix_loop:judgment",
          pass:,
          top_law: finding_value(top, :law),
          top_file: finding_value(top, :file),
          leverage: top ? Master::Cognition::Intelligence.leverage_score(top) : 0,
          uncertainty: top ? Master::Cognition::Intelligence.uncertainty_score(top) : 1.0,
          posture: top ? Master::Cognition::Intelligence.posture_for(top) : :preserve,
          scale: top ? Master::Cognition::Intelligence.judgment(top)[:scale] : :local,
        )
        remember_reasoning(pass:, findings:, files:, progressed:, top:)

        attention = Master::Cognition::Intelligence.attention_budget(findings, slots: limits["decision_choices"].to_i)
        ranked = attention[:selected]
        top = ranked.first
        @bus&.publish(
          "fix_loop:attention",
          candidates: attention[:candidates],
          selected: attention[:selected].size,
          deferred: attention[:deferred].size,
          preserved_uncertainty: !attention[:preserved_uncertainty].nil?,
        )
        @bus&.publish(
          "fix_loop:judgment",
          pass:,
          top_law: finding_value(top, :law),
          top_file: finding_value(top, :file),
          leverage: top ? Master::Cognition::Intelligence.leverage_score(top) : 0,
          uncertainty: top ? Master::Cognition::Intelligence.uncertainty_score(top) : 1.0,
          posture: top ? Master::Cognition::Intelligence.posture_for(top) : :preserve,
          scale: top ? Master::Cognition::Intelligence.judgment(top)[:scale] : :local,
        )
        remember_reasoning(pass:, findings:, files:, progressed:, top:)
        emit(
          "fix_loop:convergence_measure",
          pass:,
          violations: state[:score],
          progressed:,
          best_violations: @best_state[:score],
          quality_delta:,
        )
        state
      end

      def quality_delta
        return 0.0 if @history.empty? || @baseline.nil?

        initial = @history.first[:score]
        current = @history.last[:score]
        return 0.0 unless finite_score?(initial) && finite_score?(current)
        return 0.0 if initial.to_f.zero?

        ((initial.to_f - current.to_f) / initial.to_f).round(6)
      end

      def improving?
        return false if @history.empty?

        current = @history[-1]
        return current[:progressed] == true if @history.size < 2

        before = @history[-2]
        score_improved?(current[:score], before[:score]) || current[:progressed] == true
      end

      def note_progress!
        return false if @history.empty?

        @history[-1][:progressed] = true
        emit("fix_loop:convergence_progress", pass: @history[-1][:pass], reason: "post-observation repair")
        true
      end

      def diminishing_returns?
        cycles = limits["diminishing_cycles"].to_i
        return false if @history.size < cycles + 1

        deltas = @history.last(cycles + 1).each_cons(2).map do |a, b|
          (a[:score] - b[:score]).abs.to_f
        end
        deltas.all? { |delta| delta <= limits["diminishing_delta"].to_f }
      end

      def clean_proof(files:, pass:, clean_runs:, findings: [], required_runs: limits["clean_runs_required"].to_i)
        unreadable = unreadable_paths(files)
        unless unreadable.empty?
          emit("fix_loop:premature_exit", reason: "files_unread", files: unreadable.first(10))
          return { eligible: false, fatal: true, reason: "files unread", unreadable: }
        end

        unless findings.empty?
          emit("fix_loop:premature_exit", reason: "violations_remaining", violations: findings.size)
          return { eligible: false, fatal: false, reason: "violations remain" }
        end

        return { eligible: false, fatal: false, reason: "clean streak incomplete" } if clean_runs < required_runs.to_i

        protected = protected_floor_failures
        unless protected.empty?
          emit("fix_loop:premature_exit", reason: "protected_floor", failures: protected)
          return { eligible: false, fatal: true, reason: "constitutional floor failed", failures: protected }
        end

        {
          eligible: true,
          fatal: false,
          reason: "evidence complete",
          files_verified: Array(files).size,
          quality_delta:,
          diminishing_returns: diminishing_returns?,
          best_pass: @best_state&.fetch(:pass, pass),
        }
      end

      def strategy_for(files:, findings: [])
        return :adversarial if diminishing_returns?

        laws = Array(findings).map { |finding| finding[:law].to_s.downcase }
        return :adversarial if laws.any? { |law| law.include?("security") || law.include?("injection") || law.include?("auth") }

        languages = Array(files).map { |path| File.extname(path).downcase }.reject(&:empty?).uniq
        return :ensemble if languages.size > 1 || Array(files).size > limits["working_memory_items"].to_i
        return :incremental if Array(findings).size > limits["decision_choices"].to_i

        :consensus
      end

      def remember_reasoning(pass:, findings:, files:, progressed:, top:)
        observation = "pass #{pass}: #{Array(findings).size} finding(s) across #{Array(files).size} file(s); progressed=#{progressed}"
        hypothesis = if top
          "The highest-leverage next decision is anchored at #{finding_value(top, :file)} under #{finding_value(top, :law)}."
        elsif progressed
          "The latest mutation improved the measured state; re-observe before adding more change."
        else
          "No measured progress occurred; preserve the best state and test the hypothesis before mutating."
        end
        frame = Master::Cognition::Intelligence.decision_frame(
          observation:,
          hypothesis:,
          falsifier: "the next measured pass fails to improve the finding state or violates ground truth",
          measurement: "finding count, ground truth, clean proof and next-pass quiescence",
          source: "fix_loop:pass:#{pass}",
          selected: top ? finding_value(top, :law).to_s : "observe",
          alternatives: %w[repair preserve investigate],
          status: :uncertain,
          cause: "observe pass #{pass}",
          effect: progressed ? "measured tree change" : "no measured tree change",
        )
        @reasoning_memory ||= Master::Ground::Memory.new(root: @root)
        digest = Digest::SHA256.hexdigest(JSON.generate(frame))[0, 12]
        key = @reasoning_memory.remember_reasoning(frame, key: "reasoning/fix/#{Time.now.to_i}-#{pass}-#{digest}")
        @bus&.publish("cognition:reasoning", key:, status: frame[:status] || frame["status"], leverage: top ? Master::Cognition::Intelligence.leverage_score(top) : 0)
      rescue StandardError => e
        @bus&.publish("cognition:reasoning_inconclusive", pass:, error: "#{e.class}: #{e.message}")
      end

      def finding_value(finding, key)
        return nil unless finding
        if finding.respond_to?(key)
          return finding.public_send(key)
        end
        return finding[key] if finding.respond_to?(:key?) && finding.key?(key)
        return finding[key.to_s] if finding.respond_to?(:key?) && finding.key?(key.to_s)

        nil
      end

      def reasoning_contract(strategy:, files:, findings:)
        active_files = [Array(files).size, limits["working_memory_items"].to_i].min
        concern_cap = limits["context_switches_per_round"].to_i
        choices = limits["decision_choices"].to_i
        <<~TEXT.strip
          convergence strategy: #{strategy}
          active-file budget: #{active_files}/#{limits["working_memory_items"]} before chunking
          independent-concern budget: #{concern_cap} per reasoning round
          decision-choice budget: #{choices}; prefer elimination over branching
          observation-to-mutation ratio: at least #{limits["observation_to_mutation_ratio"]}:1 on broad structural work
          locality: keep a change beside the behavior it owns; relocate only with reference-graph proof
          progressive complexity: reveal detail only when the simpler layer is insufficient
          alternatives: generate #{limits["alternatives_min"]}-#{limits["alternatives_max"]} materially different candidates when ideation is required
          preserve best state: never trade a measured improvement for an unmeasured aesthetic
          evidence rule: unreadable, unmeasured, truncated, or simulated work is not a pass
          leverage rule: fix the change with the widest proven causal reach, not the loudest finding
          unfinished-work rule: preserve fertile uncertainty; delete only after consumer and value evidence
          #{hygiene_contract}
          #{Master::Cognition::Intelligence.orientation_contract}
          #{Master::Cognition::Intelligence.reasoning_contract}
        TEXT
      end

      private

      def limits
        @limits ||= begin
          data = Master.load_yaml(Master.limits_path)
          configured = data.is_a?(Hash) ? data["convergence_discipline"] : nil
          DEFAULTS.merge(configured.is_a?(Hash) ? configured : {})
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "convergence_discipline.config", event_bus: @bus)
          DEFAULTS
        end
      end

      def snapshot(files)
        Array(files).filter_map do |path|
          expanded = File.expand_path(path)
          next unless File.file?(expanded)

          bytes = File.binread(expanded)
          {
            path: relative(expanded),
            bytes: bytes.bytesize,
            lines: bytes.count("\n"),
            sha256: Digest::SHA256.hexdigest(bytes),
          }
        rescue StandardError => e
          emit("fix_loop:read_evidence_failed", file: relative(path), error: "#{e.class}: #{e.message}")
          nil
        end
      end

      def unreadable_paths(files)
        Array(files).filter_map do |path|
          File.binread(File.expand_path(path))
          nil
        rescue StandardError => e
          emit("fix_loop:read_evidence_failed", file: relative(path), error: "#{e.class}: #{e.message}")
          relative(path)
        end
      end

      def state_for(pass, score, snapshot)
        safe_score = score_value(score)
        {
          pass: pass.to_i,
          score: safe_score,
          snapshot_digest: digest(snapshot),
          captured_files: snapshot.size,
        }
      end

      def finite_score?(score)
        score.is_a?(Numeric) && score.respond_to?(:finite?) && score.finite?
      end

      def score_improved?(current, before)
        score_value(current) < score_value(before)
      end

      def score_value(score)
        return UNMEASURED_SCORE if score.nil?
        return UNMEASURED_SCORE if score.respond_to?(:finite?) && !score.finite?

        Integer(score)
      rescue ArgumentError, TypeError
        UNMEASURED_SCORE
      end

      def hygiene_contract
        path = File.join(Master::ROOT, "data", "fix_hygiene.yml")
        data = Master.load_yaml(path)
        prompt = data.is_a?(Hash) ? data["llm_prompt"].to_s.strip : ""
        return prompt unless prompt.empty?

        DEFAULT_HYGIENE_PROMPT
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "convergence_discipline.hygiene_contract", event_bus: @bus)
        DEFAULT_HYGIENE_PROMPT
      end

      def digest(rows)
        Digest::SHA256.hexdigest(
          Array(rows).sort_by { |row| row[:path].to_s }.map do |row|
            row.values_at(:path, :bytes, :lines, :sha256).join(":")
          end.join("|")
        )
      end

      def protected_floor_failures
        return [] unless File.expand_path(@root) == File.expand_path(Master::ROOT)

        checks = {
          File.join(Master::ROOT, "data", "soul.yml") => /PRESERVE_THEN_IMPROVE_NEVER_BREAK/,
          File.join(Master::ROOT, "data", "laws.yml") => /(?:^|\n)(?:ROBUSTNESS|SINGULARITY|LINEARITY|PROXIMITY):/,
        }
        checks.filter_map do |path, pattern|
          next if File.file?(path) && File.read(path, encoding: "UTF-8").match?(pattern)

          relative(path)
        rescue StandardError
          relative(path)
        end
      end

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        root = File.expand_path(@root)
        return path.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        path.to_s
      end

      def emit(event, **payload)
        @bus&.publish(event, payload)
      rescue StandardError
        nil
      end
    end
  end
end
