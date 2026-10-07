# frozen_string_literal: true

require "digest"

module Master
  module Fix
    # Executable remnants of the historical MASTER convergence contract.
    #
    # The old master.json/master.yml files spread these ideas across hundreds
    # of lines. The runtime needs the semantics, not another constitution-shaped
    # document.
    class ConvergenceDiscipline
      DEFAULTS = {
        "clean_runs_required" => 2,
        "diminishing_delta" => 0.001,
        "diminishing_cycles" => 3,
        "oscillation_window" => 3,
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
      end

      attr_reader :best_state

      def begin_run(files)
        @baseline = snapshot(files)
        @best_state = state_for(0, 0, @baseline)
        @history.clear
        emit("fix_loop:convergence_baseline", files: @baseline.size, digest: digest(@baseline))
        @baseline
      end

      def observe(pass:, findings:, files:, progressed:)
        current = snapshot(files)
        state = state_for(pass, Array(findings).size, current)
        @history << state.merge(progressed:)
        @best_state = state if @best_state.nil? || state[:score] < @best_state[:score]
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
        return 0.0 if initial.zero?

        ((initial - current).to_f / initial).round(6)
      end

      def diminishing_returns?
        cycles = limits["diminishing_cycles"].to_i
        return false if @history.size < cycles + 1

        deltas = @history.last(cycles).each_cons(2).map do |a, b|
          (a[:score] - b[:score]).abs.to_f
        end
        deltas.all? { |delta| delta <= limits["diminishing_delta"].to_f }
      end

      def clean_proof(files:, pass:, clean_runs:, findings: [])
        unreadable = unreadable_paths(files)
        unless unreadable.empty?
          emit("fix_loop:premature_exit", reason: "files_unread", files: unreadable.first(10))
          return { eligible: false, fatal: true, reason: "files unread", unreadable: }
        end

        unless findings.empty?
          emit("fix_loop:premature_exit", reason: "violations_remaining", violations: findings.size)
          return { eligible: false, fatal: false, reason: "violations remain" }
        end

        required = limits["clean_runs_required"].to_i
        return { eligible: false, fatal: false, reason: "clean streak incomplete" } if clean_runs < required

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

        rules = Array(findings).map { |finding| finding[:rule].to_s.downcase }
        return :adversarial if rules.any? { |rule| rule.include?("security") || rule.include?("injection") || rule.include?("auth") }

        languages = Array(files).map { |path| File.extname(path).downcase }.reject(&:empty?).uniq
        return :ensemble if languages.size > 1 || Array(files).size > limits["working_memory_items"].to_i
        return :incremental if Array(findings).size > limits["decision_choices"].to_i

        :consensus
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
          scientific method: state the observed fact, hypothesis, falsifier, and smallest measurement before acting
          alternatives: generate #{limits["alternatives_min"]}-#{limits["alternatives_max"]} materially different candidates when ideation is required
          preserve best state: never trade a measured improvement for an unmeasured aesthetic
          evidence rule: unreadable, unmeasured, truncated, or simulated work is not a pass
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
        {
          pass: pass.to_i,
          score: score.to_i,
          snapshot_digest: digest(snapshot),
          captured_files: snapshot.size,
        }
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
