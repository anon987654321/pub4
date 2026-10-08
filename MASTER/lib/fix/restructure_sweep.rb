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

        Candidate transformations:
        %<candidate_operations>s

        Any combination of these is allowed across the repository surfaces: defragment scattered concepts; decouple
        independent concerns; flatten wrappers, nesting and needless directories;
        merge equivalent logic; split unlike responsibilities; relocate code beside
        its owner; rename misleading names; reorder for importance; remove redundant
        material; reflow prose and lines; simplify accidental complexity. Behaviour,
        meaning and public contracts must not change.

        %<transformations>s

        The preservation contract is mandatory:
        %<preservation>s

        Evidence hierarchy (strongest first):
        %<evidence_hierarchy>s

        Domain adapters and smell vocabulary:
        %<domain_profile>s

        Refactoring technique playbook:
        %<refactoring_playbook>s

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
        or leave the tree harder to find one's way in? Approve only a change a
        maintainer of this code would thank you for.
        Answer with exactly one line: APPROVE, or REJECT: <reason>.

        ```diff
        %<diff>s
        ```
      TEXT

      def initialize(agent:, repo_root:, bus: nil, restructure: nil, transformation_plan: nil)
        @agent = agent
        @root = repo_root
        @bus = bus
        @transformation_plan = transformation_plan || TransformationPlan.new(root: Master::ROOT)
        @restructures = Hash.new { |cache, tree| cache[tree] = restructure || Restructure.new(repo_root:, tree:) }
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
        candidates(target, run_id).map do |problem|
          {
            problem_id: problem.id,
            files: problem.files.map { |path| relative(path) },
            laws: problem.laws,
            candidate_operations: problem.candidate_operations,
            primary_operation: problem.primary_operation,
            confidence: problem.confidence.to_s,
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
        rounds.times do |round|
          round_kept = []
          candidates(target, "#{run_id}-#{round}").first(attempts).each do |problem|
            break if kept.size + round_kept.size >= keeps

            result = attempt(problem)
            round_kept << result.value! if result&.ok?
          end
          kept.concat(round_kept)
          break if round_kept.empty?

          Master::Trace::Dmesg.status("restructure0", "round #{round + 1}, kept #{round_kept.size}, total #{kept.size}")
        end
        kept
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
          "#{found.size} finding(s) -> #{rotated.size} problem(s), "           "#{multifinding} multi-finding, #{multisignal} multi-signal, "           "#{candidate_count} candidate transformation(s)",
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

      def attempt(problem)
        path, = problem.findings.first
        tree = relative(path).split("/").first
        answer = ask(proposal(tree, problem))
        return if answer.strip == "KEEP"

        plan = Restructure::Plan.parse(answer)
        return report(problem, nil, "the answer held no plan") if plan.empty?

        review = ->(diff) { verdict(problem, plan, diff) }
        result = @restructures[tree].call(
          plan,
          message: commit_message(problem, plan),
          review:,
          allowed_operations: problem.candidate_operations,
        )
        report(problem, plan, result)
      end

      def proposal(tree, problem)
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
          refactoring_playbook: @transformation_plan.refactoring_playbook.fetch("technique_by_domain").map { |domain, techniques| "  #{domain}: #{techniques.join(", ")}" }.join("\n"),
          automatic_vetoes: @transformation_plan.automatic_vetoes.map { |veto| "  - #{veto}" }.join("\n"),
          law: problem.laws.join(", "),
          path: relative(problem.files.first),
          message: "#{problem.reason}; confidence=#{problem.confidence}; problem=#{problem.id}",
          problem_id: problem.id,
          findings:,
          candidate_operations: problem.candidate_operations.join(", "),
          context: Context.new(@root, problem.files.first, related: problem.files.drop(1)).to_s,
        )
      end

      def verdict(problem, plan, diff)
        answer = ask(
          format(
            ATTACK,
            problem_id: problem.id,
            law: problem.laws.join(", "),
            path: relative(problem.files.first),
            operations: plan.operations.join(", "),
            summary: plan.summary,
            diff:,
          ),
        ).strip
        answer.start_with?("APPROVE") ? nil : "review: #{answer.lines.first.to_s.strip[0, 200]}"
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
