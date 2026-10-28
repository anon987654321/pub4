# frozen_string_literal: true

require "digest"
require_relative "restructure"
require_relative "restructure_sweep/context"
require_relative "restructure_sweep/contracts"
require_relative "transformation_plan"
require_relative "problem_graph"

module Master
  module Fix
    # /fix treats structural consolidation as a normal repair stage. At the start
    # of a tree-level run it takes one bounded first pass; after content repair it
    # keeps sweeping until structural convergence. The model proposes the files
    # to write and delete, a second hostile turn attacks the applied diff, and
    # Restructure keeps the change only if the proof holds.
    #
    # MASTER_FIX_RESTRUCTURES=0 switches it off; MASTER_FIX_RESTRUCTURE_ATTEMPTS
    # caps the findings tried per run, each costing two model calls.
    class RestructureSweep
      ATTEMPTS = Integer(ENV.fetch("MASTER_FIX_RESTRUCTURE_ATTEMPTS", 4))
      ROUNDS = Integer(ENV.fetch("MASTER_FIX_RESTRUCTURE_ROUNDS", 4))
      KEEPS = 3
      FIRST_ATTEMPTS = 1
      FIRST_ROUNDS = 1
      FIRST_KEEPS = 1
      TREES = Contracts::BY_TREE.keys.freeze
      OPERATION_RISK = {
        "remove" => 5, "rename" => 4, "relocate" => 4, "merge" => 4,
        "split" => 3, "defragment" => 3, "decouple" => 3, "hoist" => 2,
        "flatten" => 2, "reorder" => 2, "simplify" => 2, "reflow" => 1,
        "recommend" => 1,
      }.freeze

      PROPOSE = <<~TEXT
        Restructure one underlying problem in this tree rather than fixing its findings independently.

        Autonomous surgery rules:
        - Read the archaeology below before deciding that a file is dead or should move.
        - A pure deletion is valid only when surviving production code has no reference to its path or defined constants.
        - Tests are evidence, not production callers. If a deleted test is the only consumer, say so in SUMMARY.
        - Recalculate the recursive tree census after every kept restructure; hidden nested growth is not free.
        - Reconcile the structural ratchet when the measured core gets smaller. Keep the recorded ceiling honest.

        Problem: %<problem_id>s
        Laws: %<law>s
        Why these findings were grouped: %<message>s

        Findings:
        %<findings>s

        Read-only candidate map. No source has changed during this phase:
        %<candidate_map>s

        Candidate transformations for the selected problem:
        %<candidate_operations>s

        Choose exactly one transformation for this commit. Map candidates before writing; score payoff and risk from
        evidence, compare distinct target paths, and never pad the candidate set with paraphrases. Apply one operation,
        verify it, and only then use its result as the next step's baseline.
        The transformation policy below supplies triggers, vetoes, the DRY/KISS decision table, scorecard, and proof.
        Similarity alone never justifies consolidation. Behaviour, meaning, import paths, and public contracts must not change.

        %<transformations>s

        The preservation contract is mandatory:
        %<preservation>s

        Evidence hierarchy (strongest first):
        %<evidence_hierarchy>s

        Domain adapters and smell vocabulary:
        %<domain_profile>s

        Refactoring methods (how to work):
        %<refactoring_methods>s

        Refactoring technique playbook:
        %<refactoring_playbook>s

        Refactoring checks (what a kept change must satisfy):
        %<refactoring_checks>s

        Automatic vetoes:
        %<automatic_vetoes>s

        The tree, and the contracts to keep:
        %<contracts>s

        If no restructure is both sound and clearly better, answer exactly: KEEP
        The context below numbers each line for reference; never copy the numbers.
        Otherwise answer in exactly this format, whole file contents, no code fences:
        SUMMARY: <one line: what moved where, and why>
        OPERATIONS: <one or more candidate transformation names, comma-separated, in constitutional order>
        === WRITE <path from the repository root, e.g. MASTER/lib/fix/x.rb>
        <complete file content>
        === DELETE <path from the repository root>
        === END

        %<context>s
      TEXT

      ATTACK = <<~TEXT
        A restructure, proposed for problem %<problem_id>s (%<law>s) at %<path>s:
        operations: %<operations>s
        %<summary>s

        Attack it. Does it change behaviour, break a caller, a require, load order,
        or a Zeitwerk path and constant pair? Does it only move complexity around,
        or leave the tree harder to find one's way in? Does it merge code that only
        looks alike, whose units change for different reasons, or abstract fewer
        than three sites? Does it flatten depth that mirrors a real domain
        boundary? Does the old public import path survive? Compare the measured scorecard below with the baseline;
        each measured regression needs an operation-specific justification, while unmeasured dimensions stay inconclusive.
        A tie keeps the current tree. Approve only a change a maintainer would thank you for.
        Scorecard evidence: %<scorecard>s
        Answer with exactly one line: APPROVE: <evidence and reasons any measured regressions are acceptable>, or REJECT: <reason>.
        A bare APPROVE is invalid. If any measured regression lacks an operation-specific justification, reject.

        ```diff
        %<diff>s
        ```
      TEXT

      def initialize(agent:, repo_root:, bus: nil, restructure: nil, transformation_plan: nil,
                     ground_truth: nil, preserve_user_intent: nil)
        @agent = agent
        @root = repo_root
        @bus = bus
        @transformation_plan = transformation_plan || TransformationPlan.new(root: Master::ROOT)
        @ground_truth = ground_truth
        @preserve_user_intent = preserve_user_intent
        @restructures = Hash.new do |cache, tree|
          cache[tree] = restructure || Restructure.new(
            repo_root:,
            tree:,
            ground_truth: @ground_truth,
            preserve_user_intent: @preserve_user_intent,
          )
        end
      end

      def run(target:, run_id:, phase: :normal)
        return [] if ENV["MASTER_FIX_RESTRUCTURES"] == "0"

        sweep_targets(target).flat_map do |tree_target|
          run_tree(
            tree_target,
            "#{run_id}-#{File.basename(tree_target)}",
            attempts: phase == :structure_first ? FIRST_ATTEMPTS : ATTEMPTS,
            rounds: phase == :structure_first ? FIRST_ROUNDS : ROUNDS,
            keeps: phase == :structure_first ? FIRST_KEEPS : KEEPS,
          )
        end
      end

      # Read-only structural planning used by --dry-run. It performs the same
      # deterministic finding clustering and candidate ordering as the live restructure
      # stage, but never asks the model, writes files, commits, or pushes.
      def preview(target:, run_id: "preview")
        ranked_candidate_map(candidates(target, run_id)).map do |row|
          problem = row.fetch(:problem)
          {
            problem_id: problem.id,
            files: problem.files.map { |path| relative(path) },
            laws: problem.laws,
            candidate_operations: problem.candidate_operations,
            primary_operation: problem.primary_operation,
            confidence: problem.confidence.to_s,
            payoff: row.fetch(:payoff),
            risk: row.fetch(:risk),
            payoff_risk: row.fetch(:ratio),
            evidence_hierarchy: @transformation_plan.evidence_hierarchy,
            domain_adapters: @transformation_plan.domain_adapters,
            smell_catalog: @transformation_plan.smell_catalog,
            refactoring_playbook: @transformation_plan.refactoring_playbook,
            reason: problem.reason,
          }
        end
      end

      def run_tree(target, run_id, attempts:, rounds:, keeps:)
        kept = []
        terminal = :limit_reached
        rounds.times do |round|
          break if kept.size >= keeps

          ranked = ranked_candidate_map(candidates(target, "#{run_id}-#{round}"))
          if ranked.empty?
            terminal = :done
            break
          end
          problems = ranked.map { |row| row.fetch(:problem) }
          candidate_map = render_candidate_map(ranked)

          round_kept = []
          vetoes = 0
          problems.first(attempts).each do |problem|
            break if kept.size + round_kept.size >= keeps

            result = attempt(problem, candidate_map:)
            round_kept << result.value! if result&.ok?
            break if result&.ok?
            vetoes += 1 if policy_veto?(result)
          end
          kept.concat(round_kept)
          if round_kept.empty?
            terminal =
              if problems.size > attempts
                :limit_reached
              elsif vetoes.positive? && vetoes == problems.size
                :veto
              else
                :plateau
              end
            break
          end

          Master::Trace::Dmesg.status("restructure0", "round #{round + 1}, kept #{round_kept.size}, total #{kept.size}")
          terminal = :limit_reached if kept.size >= keeps || round == rounds - 1
        end
        if terminal == :limit_reached
          terminal = :done if candidates(target, "#{run_id}-final").empty?
        end
        Master::Trace::Dmesg.status("restructure0", "terminal=#{terminal} kept=#{kept.size}")
        @bus&.publish("fix_loop:restructure_exit", target: relative(target), state: terminal.to_s.upcase, kept: kept.size)
        kept
      end

      def ranked_candidate_map(problems)
        score_min, score_max = @transformation_plan.candidate_map_policy.fetch("score_range").map(&:to_i)
        Array(problems).map do |problem|
          signal_count = problem.findings.size + [problem.laws.size - 1, 0].max + [problem.files.size - 1, 0].max
          payoff = [[signal_count, score_min].max, score_max].min
          risk = (problem.candidate_operations.map { |operation| OPERATION_RISK.fetch(operation, score_max) }.max || score_max)
            .clamp(score_min, score_max)
          { problem:, payoff:, risk:, ratio: payoff.to_f / risk }
        end.sort_by do |row|
          [-row.fetch(:ratio), -row.fetch(:payoff), row.fetch(:risk), row.fetch(:problem).id]
        end
      end

      # The map is evidence-backed, scored, and read-only. If the tree has fewer
      # than the requested number of candidates, report the shortfall instead of
      # inventing filler or repeating the same move under different names.
      def render_candidate_map(rows)
        wanted = Integer(@transformation_plan.candidate_map_policy.fetch("minimum_alternatives"))
        min_paths = Integer(@transformation_plan.candidate_map_policy.fetch("minimum_distinct_target_paths"))
        distinct_paths = rows.flat_map { |row| row.fetch(:problem).files }.uniq
        score_max = @transformation_plan.candidate_map_policy.fetch("score_range").last.to_i
        shown = rows.first(30).map do |row|
          problem = row.fetch(:problem)
          findings = problem.findings.map { |path, law, message, _related| "#{relative(path)} #{law} #{message}" }
          format(
            "  %s payoff=%d/%d risk=%d/%d ratio=%.2f operation=%s paths=%s evidence=%s",
            problem.id, row.fetch(:payoff), score_max, row.fetch(:risk), score_max, row.fetch(:ratio),
            problem.candidate_operations.join(","), problem.files.map { |path| relative(path) }.join(","),
            findings.join(" | "),
          )
        end
        shortfall = [wanted - rows.size, 0].max
        path_shortfall = [min_paths - distinct_paths.size, 0].max
        [
          "Evidence-backed candidates: #{rows.size}; distinct target paths: #{distinct_paths.size}.",
          "Requested minimums: #{wanted} candidates and #{min_paths} distinct target paths; shortfalls: #{shortfall} candidates and #{path_shortfall} paths.",
          "Shortfalls are reported, never padded. Payoff/risk is a deterministic ranking aid, not an equivalence proof.",
          *shown,
          (rows.size > shown.size ? "  omitted #{rows.size - shown.size} lower-ranked candidates" : nil),
        ].compact.join("\n")
      end

      def policy_veto?(result)
        result.is_a?(Result) && !result.ok? &&
          result.message.to_s.match?(/MIXED_COMMIT|BATCH_DELETE|UNALIASED_MOVE|restructure refused|immutable|off limits|outside .*policy|stale read required/i)
      end

      def sweep_targets(target)
        expanded = File.expand_path(target.to_s, @root)
        return TREES.filter_map do |tree|
          path = File.join(@root, tree)
          path if File.directory?(path)
        end if expanded == File.expand_path(@root)

        return [] unless TREES.include?(File.basename(expanded))
        return [] unless File.dirname(expanded) == File.expand_path(@root)

        [expanded]
      end

      # [path, law, message, related_paths] for each repository-surface finding, smallest moves first;
      # within a rule the order rotates by run, so every finding comes up. Dead
      # subtrees and cross-file architecture defects carry their evidence paths
      # into the proposal rather than collapsing to one filename.
      def candidates(target, run_id)
        found = Context.structural_findings(target)
        problems = ProblemGraph.new(plan: @transformation_plan).call(found)
        return [] if problems.empty?

        seed = Digest::SHA256.hexdigest(run_id.to_s)[0, 8].to_i(16)
        rotated = problems.rotate(seed % problems.size)
        multifinding = rotated.count { |problem| problem.size > 1 }
        multisignal = rotated.count(&:multi_signal?)
        candidate_count = rotated.sum { |problem| problem.candidate_operations.size }

        Master::Trace::Dmesg.status(
          "restructure0",
          "#{found.size} finding(s) -> #{rotated.size} problem(s), " \
          "#{multifinding} multi-finding, #{multisignal} multi-signal, " \
          "#{candidate_count} candidate transformation(s)",
        )
        @bus&.publish(
          "fix_loop:restructure_problems",
          target: relative(target),
          findings: found.size,
          problems: rotated.size,
          multi_finding: multifinding,
          multi_signal: multisignal,
          candidates: candidate_count,
        )
        rotated
      end

      private

      def attempt(problem, candidate_map: "")
        path, = problem.findings.first
        tree = relative(path).split("/").first
        baseline_scorecard = Restructure::Proof.for(tree, @root).scorecard
        answer = ask(proposal(tree, problem, scorecard: baseline_scorecard, candidate_map:))
        return if answer.strip == "KEEP"

        plan = Restructure::Plan.parse(answer)
        return report(problem, nil, "the answer held no plan") if plan.empty?

        review = ->(diff) { verdict(problem, plan, diff, scorecard_before: baseline_scorecard) }
        result = @restructures[tree].call(
          plan,
          message: commit_message(problem, plan),
          review:,
          allowed_operations: problem.candidate_operations,
        )
        report(problem, plan, result)
      end

      def proposal(tree, problem, scorecard: nil, candidate_map: "")
        scorecard ||= Restructure::Proof.for(tree, @root).scorecard
        findings = problem.findings.map do |path, rule, message, related|
          related = Array(related).map { |item| relative(item) }.reject { |item| item == relative(path) }
          [
            "#{relative(path)}: #{rule}: #{message}",
            (related.empty? ? nil : "  related: #{related.first(8).join(", ")}"),
          ].compact.join("\n")
        end.join("\n")

        format(
          PROPOSE,
          transformations: @transformation_plan.prompt,
          preservation: @transformation_plan.preservation_contract.map { |key, value| "  #{key}: #{value}" }.join("\n"),
          contracts: Contracts.for(tree).strip,
          evidence_hierarchy: @transformation_plan.evidence_hierarchy.map { |entry| "  #{entry.fetch("id")}: #{entry.fetch("practice")}" }.join("\n"),
          domain_profile: @transformation_plan.domain_adapters.map { |domain, adapter| "  #{domain}: #{adapter}; smells=#{@transformation_plan.smell_catalog.fetch(domain, []).join(", ")}" }.join("\n"),
          refactoring_methods: playbook_lines("methods") { |entry| "  #{entry.fetch("id")}: #{entry.fetch("action")}" },
          refactoring_playbook: playbook_lines("technique_by_domain") { |domain, techniques| "  #{domain}: #{techniques.join(", ")}" },
          refactoring_checks: playbook_lines("checks") { |check| "  - #{check}" },
          automatic_vetoes: @transformation_plan.automatic_vetoes.map { |veto| "  - #{veto}" }.join("\n"),
          law: problem.laws.join(", "),
          path: relative(problem.files.first),
          message: "#{problem.reason}; confidence=#{problem.confidence}; problem=#{problem.id}",
          problem_id: problem.id,
          findings:,
          candidate_operations: problem.candidate_operations.join(", "),
          candidate_map:,
          context: Context.new(
            @root, problem.files.first, related: problem.files.drop(1), scorecard:,
            co_change_window: @transformation_plan.scorecard_policy.fetch("history_window_commits"),
          ).to_s,
        )
      end

      # Methods and checks were validated at boot but never shown to the model;
      # a declared method no prompt carries governs nothing.
      def playbook_lines(section, &)
        @transformation_plan.refactoring_playbook.fetch(section).map(&).join("\n")
      end

      def verdict(problem, plan, diff, scorecard_before: {})
        tree = relative(problem.files.first).split("/").first
        scorecard_after = Restructure::Proof.for(tree, @root).scorecard(extra_paths: plan.paths)
        numeric_delta = scorecard_before.filter_map do |name, value|
          next unless value.is_a?(Numeric) && scorecard_after[name].is_a?(Numeric)

          [name, scorecard_after[name] - value]
        end.to_h
        scorecard_text = "before: #{scorecard_before.inspect}\nafter: #{scorecard_after.inspect}\ndelta: #{numeric_delta.inspect}"
        answer = ask(
          format(
            ATTACK,
            problem_id: problem.id,
            law: problem.laws.join(", "),
            path: relative(problem.files.first),
            operations: plan.operations.join(", "),
            summary: plan.summary,
            scorecard: scorecard_text,
            diff:,
          ),
        ).strip
        approval = answer.match(/\AAPPROVE:\s+\S.{19,}\z/)
        approval ? nil : "review: #{answer.lines.first.to_s.strip[0, 200]}"
      end

      def commit_message(problem, plan)
        title = plan.summary.empty? ? "Restructure #{relative(problem.files.first)}" : plan.summary
        body = [
          "Address laws #{problem.laws.join(", ")} for problem #{problem.id}.",
          "Verify the change with hostile review, parsing, eager load, boot self-test, and related tests.",
        ].join("\n\n")
        [title, body].join("\n\n")
      end

      def report(problem, plan, result)
        ok = result.is_a?(Result) && result.ok?
        text = if ok then "kept: #{plan.summary}"
               elsif result.is_a?(Result) then result.message
               else result.to_s
               end
        evidence = ok ? result.value!.fetch(:evidence, nil) : nil
        operation = plan&.operations&.last || problem.primary_operation
        Master::Trace::Dmesg.status(
          "restructure0",
          "#{operation} problem=#{problem.id} signals=#{problem.size} #{problem.laws.join(",")} #{relative(problem.files.first)}: #{text[0, 140]}",
        )
        @bus&.publish(
          "fix_loop:restructure",
          path: relative(problem.files.first),
          law: problem.laws.join(","),
          laws: problem.laws,
          problem_id: problem.id,
          operation:,
          candidate_operations: problem.candidate_operations,
          operations: plan&.operations || [],
          confidence: problem.confidence,
          findings: problem.size,
          ok:,
          message: text[0, 300],
          evidence:,
        )
        result.is_a?(Result) ? result : nil
      end

      def ask(prompt)
        @agent.ask(prompt, operation: :restructure).to_s
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.restructure_sweep")
        ""
      end

      def relative(path) = path.to_s.delete_prefix("#{@root}/")
    end
  end
end
