# frozen_string_literal: true

require "digest"
require "json"
require_relative "../cognition/intelligence"
require_relative "../cognition/state"
require_relative "../cognition/self_model"

module Master
  module Fix
    # Executable remnants of the historical MASTER convergence contract.
    #
    # The old master.json/master.yml files spread these ideas across hundreds
    # of lines. The runtime needs the semantics, not another constitution-shaped
    # document.
    class ConvergenceDiscipline
      UNMEASURED_SCORE = 1_000_000_000
      CHECKPOINT_VERSION = 1
      CHECKPOINT_HISTORY = 6

      DEFAULT_HYGIENE_PROMPT = <<~TEXT.strip
        fix hygiene contract (enforce on every mutation in this /fix pass):

        1. numeric ranks: never .to_i/.to_int on values that may be Infinity/NaN; use finite sentinels
        2. extract-then-match: if you strip a body from source, the next pattern must match that body
        3. regex fixtures: every new extractor includes a unit fixture of the real surface form
        4. bare-invoke / defaults: one dispatch path; update tests and comments in the same change
        5. source pins: assert stable public names, never match against whole multi-MB files
        6. event topics: literal string publishers; no stale aliases (see data/event_topics.yml)
        7. dual paths: after early return/exit, delete or share one function with the later twin
        8. checks: label SKIPPED vs FAILED vs crash
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

      def initialize(root:, bus: nil, cognition_root: nil)
        @root = File.expand_path(root)
        @cognition_root = File.expand_path(cognition_root || root)
        @bus = bus
        @history = []
        @best_state = nil
        @baseline = nil
        @critical_baseline = nil
        @initial_score = nil
        @observation_count = 0
        @reasoning_memory = nil
      end

      attr_reader :best_state, :history

      def begin_run(files, preserve_run_baseline: false)
        @baseline = snapshot(files)
        unless preserve_run_baseline
          @authority_baseline = authority_state
          @critical_baseline = snapshot(critical_source_files)
        end
        @best_state = state_for(0, UNMEASURED_SCORE, @baseline)
        @history.clear
        @initial_score = nil
        @observation_count = 0
        emit("fix_loop:convergence_baseline", files: @baseline.size, digest: digest(@baseline),
                                                  authority_digest: digest_authorities(@authority_baseline),
                                                  critical_files: Array(@critical_baseline).size)
        @baseline
      end

      Decision = Struct.new(:action, :reason, keyword_init: true)

      def observe(pass:, findings:, files:, progressed:)
        findings = Array(findings)
        current = snapshot(files)
        identities = findings.map { |finding| finding_identity(finding) }.uniq.sort
        state = state_for(pass, findings.size, current).merge(
          finding_ids: identities,
          finding_digest: Digest::SHA256.hexdigest(identities.join("\0")),
          risk_vector: risk_vector(findings),
        )
        previous = @history.last
        @initial_score = state[:score] if @observation_count.zero?
        @observation_count += 1
        @history << state.merge(progressed:)
        if @best_state.nil? || @best_state[:score] == UNMEASURED_SCORE || state_better?(state, @best_state)
          @best_state = state
        end
        previous_ids = Array(previous && previous[:finding_ids])
        resolved = previous_ids - identities
        introduced = identities - previous_ids

        global_top = Master::Cognition::Intelligence.rank_by_leverage(findings).first
        judge(pass:, findings:, files:, progressed:, top: global_top)

        attention = Master::Cognition::Intelligence.attention_budget(findings, slots: limits["decision_choices"].to_i)
        @bus&.publish(
          "fix_loop:attention",
          candidates: attention[:candidates],
          selected: attention[:selected].size,
          deferred: attention[:deferred].size,
          preserved_uncertainty: !attention[:preserved_uncertainty].nil?,
        )
        # The attention budget can pick a different finding than the global top; only then is a
        # second judgment a different fact. Otherwise it was the same event and the same memory
        # write, published twice.
        selected_top = attention[:selected].first
        judge(pass:, findings:, files:, progressed:, top: selected_top) unless same_finding?(global_top, selected_top)
        emit(
          "fix_loop:convergence_measure",
          pass:,
          violations: state[:score],
          progressed:,
          best_violations: @best_state[:score],
          quality_delta:,
          finding_digest: state[:finding_digest],
          finding_ids_resolved: resolved.size,
          finding_ids_introduced: introduced.size,
          risk_vector: state[:risk_vector],
        )
        state
      end

      def judge(pass:, findings:, files:, progressed:, top:)
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
      end

      def same_finding?(first, second)
        return true if first.equal?(second)
        return false if first.nil? || second.nil?

        %i[law file line].all? { |key| finding_value(first, key) == finding_value(second, key) }
      end

      def quality_delta
        return 0.0 if @history.empty? || @baseline.nil?

        initial = @initial_score || @history.first[:score]
        current = @history.last[:score]
        return 0.0 unless finite_score?(initial) && finite_score?(current)
        return 0.0 if initial.to_f.zero?

        ((initial.to_f - current.to_f) / initial.to_f).round(6)
      end

      # Progress is activity; improvement is a measured reduction in risk.
      # An initial observation or an unchanged risk vector cannot justify a
      # larger pass budget merely because a file was written.
      def improving?
        return false if @history.size < 2

        current = @history[-1]
        before = @history[-2]
        comparison = current[:risk_vector] <=> before[:risk_vector]
        comparison&.negative? == true
      end

      def adaptive_decision(deadline_expired:, pass_limit:, absolute_limit:)
        return Decision.new(action: :stop, reason: :deadline) if deadline_expired
        return Decision.new(action: :stop, reason: :absolute_limit) if pass_limit.to_i >= absolute_limit.to_i
        return Decision.new(action: :extend, reason: :measured_improvement) if improving?

        Decision.new(action: :stop, reason: :no_improvement)
      end

      # Compact index into terminal evidence; the source snapshots and verifier
      # output remain the primary records.
      def receipt
        latest = @history.last || {}
        {
          version: 1,
          observations: @observation_count,
          pass: latest[:pass],
          files_observed: latest[:captured_files],
          findings: latest[:score],
          finding_digest: latest[:finding_digest],
          risk_vector: latest[:risk_vector],
          snapshot_digest: latest[:snapshot_digest],
          best_pass: @best_state&.fetch(:pass, nil),
          quality_delta:,
          authority_digest: digest_authorities(@authority_baseline),
        }.compact
      end

      # Durable, bounded convergence evidence. Older observations retain their
      # measurements; only the latest needs finding identities for the next diff.
      def checkpoint_state
        rows = @history.last(CHECKPOINT_HISTORY).map { |row| row.transform_keys(&:to_s) }
        rows.each { |row| row.delete("finding_ids") }
        rows[-1]["finding_ids"] = Array(@history.last[:finding_ids]) if rows.any? && @history.last
        best = @best_state&.transform_keys(&:to_s)
        best&.delete("finding_ids")
        {
          "version" => CHECKPOINT_VERSION,
          "baseline_present" => !@baseline.nil?,
          "authority_baseline" => @authority_baseline,
          "critical_baseline" => Array(@critical_baseline).map { |row| row.transform_keys(&:to_s) },
          "history" => rows,
          "best_state" => best,
          "initial_score" => @initial_score,
          "observation_count" => @observation_count,
        }
      end

      # Restore only known fields and only a structurally valid checkpoint.
      # A rejected optional checkpoint leaves begin_run's fresh baseline intact.
      def restore_checkpoint(checkpoint)
        return false unless checkpoint.is_a?(Hash)
        return false unless checkpoint["version"] == CHECKPOINT_VERSION
        return false unless checkpoint["baseline_present"] == true

        authorities = checkpoint["authority_baseline"]
        return false unless authorities.is_a?(Hash) && !authorities.empty?
        return false unless authorities.all? { |path, hash| path.is_a?(String) && hash.to_s.match?(/\A[0-9a-f]{64}\z/) }

        critical = checkpoint["critical_baseline"]
        return false unless critical.is_a?(Array) && critical.all? do |row|
          row.is_a?(Hash) && row["path"].is_a?(String) && row["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
        end

        history = checkpoint["history"]
        return false unless history.is_a?(Array) && history.size <= CHECKPOINT_HISTORY
        normalized_history = history.map { |row| normalize_checkpoint_observation(row) }
        return false unless normalized_history.all? { |row| valid_checkpoint_observation?(row) }

        best = checkpoint["best_state"] && normalize_checkpoint_observation(checkpoint["best_state"])
        return false if best && !best[:score].is_a?(Numeric)

        count = Integer(checkpoint["observation_count"])
        return false if count.negative? || count < history.size
        return false if count.positive? && (history.empty? || best.nil?)
        initial_score = checkpoint["initial_score"]
        return false unless initial_score.nil? || initial_score.is_a?(Numeric)
        return false if count.positive? && initial_score.nil?

        @baseline = []
        @authority_baseline = authorities.dup
        @critical_baseline = critical.map { |row| normalize_checkpoint_snapshot(row) }
        @history = normalized_history
        @best_state = best
        @initial_score = initial_score
        @observation_count = count
        true
      rescue ArgumentError, TypeError
        false
      end

      private

      def normalize_checkpoint_observation(row)
        raise TypeError, "checkpoint observation must be a hash" unless row.is_a?(Hash)

        allowed = %w[pass score snapshot_digest captured_files finding_ids finding_digest risk_vector progressed]
        row.each_with_object({}) do |(key, value), out|
          name = key.to_s
          next unless allowed.include?(name)

          out[name.to_sym] = value
        end
      end

      def normalize_checkpoint_snapshot(row)
        {
          path: row["path"],
          bytes: row["bytes"],
          lines: row["lines"],
          sha256: row["sha256"],
        }
      end

      def valid_checkpoint_observation?(row)
        row[:pass].is_a?(Integer) &&
          row[:score].is_a?(Numeric) &&
          row[:snapshot_digest].is_a?(String) &&
          row[:captured_files].is_a?(Integer) &&
          row[:risk_vector].is_a?(Array) &&
          row[:risk_vector].size == 4 &&
          row[:risk_vector].all? { |value| value.is_a?(Numeric) } &&
          (!row.key?(:finding_ids) || (row[:finding_ids].is_a?(Array) && row[:finding_ids].all? { |id| id.is_a?(String) }))
      end

      public

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
        unless complete_authority_baseline?
          emit("fix_loop:premature_exit", reason: "authority_baseline_unavailable")
          return { eligible: false, fatal: true, reason: "governing authority baseline unavailable" }
        end

        authority_changes = changed_authorities
        unless authority_changes.empty?
          emit("fix_loop:premature_exit", reason: "governing_authority_changed", files: authority_changes)
          return {
            eligible: false,
            fatal: true,
            reason: "governing authority changed during run; reload and re-evaluate under the new law",
            authority_changes:,
          }
        end

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

        critical_changes = safety_critical_changes(files)
        unless critical_changes.empty?
          syntax_failures = independent_ruby_parse(critical_source_files)
          unless syntax_failures.empty?
            emit("fix_loop:premature_exit", reason: "independent_parser_failed", failures: syntax_failures)
            return {
              eligible: false,
              fatal: true,
              reason: "independent Ruby parse failed after repair-engine changes",
              critical_changes:,
              syntax_failures:,
            }
          end
          emit("fix_loop:independent_verification", changed_paths: critical_changes, ruby_files_parsed: critical_source_files.count { |path| File.extname(path) == ".rb" })
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

        historical_strategy = measured_repair_strategy
        return :adversarial if historical_strategy == :adversarial

        languages = Array(files).map { |path| File.extname(path).downcase }.reject(&:empty?).uniq
        return :ensemble if languages.size > 1 || Array(files).size > limits["working_memory_items"].to_i
        return :ensemble if historical_strategy == :ensemble
        return :incremental if Array(findings).size > limits["decision_choices"].to_i

        :consensus
      end

      # Only a structurally valid, restored state with enough labelled outcomes
      # may change council strategy. Missing, corrupt, or sparse history is not a
      # negative or positive signal; the established default remains in force.
      def measured_repair_strategy
        path = File.join(@cognition_root, Master::Cognition::State::PATH)
        state = Master::Cognition::State.load(path)
        return unless state.load_status == "restored"

        assessment = Master::Cognition::SelfModel.new.decision_posture(state.self_model, capability: "code_repair")
        assessment[:strategy] if assessment[:posture] == :measured
      rescue StandardError
        nil
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

      def finding_identity(finding)
        law = finding_value(finding, :law) || finding_value(finding, :law_id) || finding_value(finding, :rule)
        file = finding_value(finding, :file) || finding_value(finding, :path)
        fingerprint = finding_value(finding, :fingerprint).to_s.strip
        explicit = fingerprint.empty? ? finding_value(finding, :evidence_key).to_s.strip : fingerprint
        if !explicit.empty?
          identity = [law, file, explicit]
        else
          line = finding_value(finding, :line)
          message = finding_value(finding, :message).to_s.gsub(/\s+/, " ").strip.downcase
          identity = [law, file, line, message.empty? ? finding.to_s : message]
        end
        Digest::SHA256.hexdigest(identity.map { |value| value.to_s.strip }.join("\0"))[0, 24]
      end

      # Lexicographic risk ordering means fewer warnings cannot compensate for
      # an increase in critical or error-level findings.
      def risk_vector(findings)
        counts = [0, 0, 0, 0]
        Array(findings).each do |finding|
          severity = finding_value(finding, :severity).to_s.downcase
          index = if severity.match?(/critical|blocker|fatal|veto/)
            0
          elsif severity.match?(/error|high|severe/)
            1
          elsif severity.match?(/info|advisory|low/)
            3
          else
            2
          end
          counts[index] += 1
        end
        counts
      end

      def state_better?(candidate, known)
        candidate_vector = candidate[:risk_vector]
        known_vector = known[:risk_vector]
        return candidate[:score] < known[:score] unless candidate_vector && known_vector

        comparison = candidate_vector <=> known_vector
        comparison.negative? || (comparison.zero? && candidate[:score] < known[:score])
      end

      def finding_value(finding, key)
        return unless finding
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

      def authority_paths
        %w[soul.yml laws.yml].map { |name| File.join(Master::ROOT, "data", name) }
      end

      def authority_state
        authority_paths.to_h do |path|
          value = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
          [relative(path), value]
        rescue StandardError => e
          emit("fix_loop:authority_fingerprint_failed", file: relative(path), error: "#{e.class}: #{e.message}")
          [relative(path), nil]
        end
      end

      def complete_authority_baseline?
        @authority_baseline.is_a?(Hash) &&
          !@authority_baseline.empty? &&
          @authority_baseline.values.all? { |value| value.to_s.match?(/\A[0-9a-f]{64}\z/) }
      end

      def changed_authorities
        current = authority_state
        (@authority_baseline.keys | current.keys).select do |path|
          @authority_baseline[path] != current[path]
        end.sort
      end

      def digest_authorities(state)
        return unless state.is_a?(Hash)

        Digest::SHA256.hexdigest(state.sort.map { |path, hash| "#{path}:#{hash}" }.join("\0"))
      end

      def critical_source_files
        paths = [
          File.join(@root, "MASTER", "data", "laws.yml"),
          File.join(@root, "MASTER", "data", "soul.yml"),
        ]
        patterns = %w[
          MASTER/lib/fix/**/*.rb
          MASTER/lib/review/scan/**/*.rb
          MASTER/law/*.rb
        ]
        paths.concat(patterns.flat_map { |pattern| Dir.glob(File.join(@root, pattern)) })
        paths.select { |path| File.file?(path) }.uniq.sort
      end

      def safety_critical_changes(_files)
        before = Array(@critical_baseline).to_h { |row| [row[:path], row[:sha256]] }
        after = snapshot(critical_source_files).to_h { |row| [row[:path], row[:sha256]] }
        (before.keys | after.keys).select do |path|
          before[path] != after[path]
        end.sort
      end

      def independent_ruby_parse(files)
        return Array(files).select { |path| File.extname(path) == ".rb" }.map do |path|
          { file: relative(path), error: "RubyVM::AbstractSyntaxTree unavailable" }
        end unless defined?(RubyVM::AbstractSyntaxTree)

        Array(files).filter_map do |path|
          next unless File.extname(path) == ".rb"

          RubyVM::AbstractSyntaxTree.parse_file(path)
          nil
        rescue StandardError, SyntaxError => e
          { file: relative(path), error: "#{e.class}: #{e.message.to_s[0, 240]}" }
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
          end.join("|"),
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
