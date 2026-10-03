# frozen_string_literal: true

require "digest"
require_relative "restructure"
require_relative "restructure_sweep/context"
require_relative "restructure_sweep/contracts"
require_relative "transformation_plan"

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
      RULE_OPERATIONS = {
        "DEAD_SUBTREE" => "defragment",
        "PARALLEL_HIERARCHY" => "merge",
        "CYCLIC_DEPENDENCY" => "decouple",
        "FILE_SPRAWL" => "flatten",
        "NO_GOD_CLASS" => "split",
        "SMALL_FILES" => "split",
        "JS_MODULE_SIZE" => "split",
      }.freeze
      TREES = Contracts::BY_TREE.keys.freeze

      PROPOSE = <<~TEXT
        Restructure part of this tree to remove one structural finding.

        Autonomous surgery rules:
        - Read the archaeology below before deciding that a file is dead or should move.
        - A pure deletion is valid only when surviving production code has no reference to its path or defined constants.
        - Tests are evidence, not production callers. If a deleted test is the only consumer, say so in SUMMARY.
        - Recalculate the recursive tree census after every kept restructure; hidden nested growth is not free.
        - Reconcile the structural ratchet when the measured core gets smaller. Keep the recorded ceiling honest.

        Finding: %<rule>s at %<path>s: %<message>s

        Any combination of these is allowed: defragment scattered concepts; decouple
        independent concerns; flatten wrappers, nesting and needless directories;
        merge equivalent logic; split unlike responsibilities; relocate code beside
        its owner; rename misleading names; reorder for importance; remove redundant
        material; reflow prose and lines; simplify accidental complexity. Behaviour,
        meaning and public contracts must not change.

        %<transformations>s

        The preservation contract is mandatory:
        %<preservation>s

        The tree, and the contracts to keep:
        %<contracts>s

        If no restructure is both sound and clearly better, answer exactly: KEEP
        The context below numbers each line for reference; never copy the numbers.
        Otherwise answer in exactly this format, whole file contents, no code fences:
        SUMMARY: <one line: what moved where, and why>
        === WRITE <path from the repository root, e.g. MASTER/lib/fix/x.rb>
        <complete file content>
        === DELETE <path from the repository root>
        === END

        %<context>s
      TEXT

      ATTACK = <<~TEXT
        A restructure, proposed to remove %<rule>s at %<path>s:
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

      def run_tree(target, run_id, attempts:, rounds:, keeps:)
        kept = []
        rounds.times do |round|
          round_kept = []
          candidates(target, "#{run_id}-#{round}").first(attempts).each do |finding|
            break if kept.size + round_kept.size >= keeps

            result = attempt(finding)
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

      # [path, rule, message, related_paths] for each structural finding, smallest moves first;
      # within a rule the order rotates by run, so every finding comes up. Dead
      # subtrees and cross-file architecture defects carry their evidence paths
      # into the proposal rather than collapsing to one filename.
      def candidates(target, run_id)
        found = Context.structural_findings(target)
        seed = Digest::SHA256.hexdigest(run_id.to_s)[0, 8].to_i(16)
        grouped = found.group_by { |_path, rule, _message| RULE_OPERATIONS.fetch(rule, "recommend") }
        ordered = grouped.keys.sort_by { |operation| @transformation_plan.operation(operation).position rescue 999 }
        ordered.flat_map do |operation|
          group = grouped.fetch(operation)
          group.rotate(seed % group.size)
        end
      end

      private

      def attempt(finding)
        path, rule, message, related = finding
        tree = relative(path).split("/").first
        answer = ask(proposal(tree, rule, path, message, related:))
        return if answer.strip == "KEEP"

        plan = Restructure::Plan.parse(answer)
        return report(finding, nil, "the answer held no plan") if plan.empty?

        review = ->(diff) { verdict(rule, path, plan, diff) }
        report(finding, plan, @restructures[tree].call(plan, message: commit_message(rule, path, plan), review:))
      end

      def proposal(tree, rule, path, message, related: [])
        format(PROPOSE, transformations: @transformation_plan.prompt,
                        preservation: @transformation_plan.preservation_contract.map { |key, value| "  #{key}: #{value}" }.join("\n"),
                        contracts: Contracts.for(tree).strip, rule:, path: relative(path), message:,
                        context: Context.new(@root, path, related:).to_s)
      end

      def verdict(rule, path, plan, diff)
        answer = ask(format(ATTACK, rule:, path: relative(path), summary: plan.summary, diff:)).strip
        answer.start_with?("APPROVE") ? nil : "review: #{answer.lines.first.to_s.strip[0, 200]}"
      end

      def commit_message(rule, path, plan)
        "refactor: #{plan.summary.empty? ? "restructure #{relative(path)}" : plan.summary}\n\n" \
          "Removes #{rule} at #{relative(path)}. Restructured by /fix after the repair passes: " \
          "a hostile review approved the diff, and parse, eager load, the boot self-test and " \
          "the related tests held."
      end

      def report(finding, plan, result)
        path, rule, = finding
        ok = result.is_a?(Result) && result.ok?
        text = if ok then "kept: #{plan.summary}"
               elsif result.is_a?(Result) then result.message
               else result.to_s
               end
        Master::Trace::Dmesg.status("restructure0", "#{rule} #{relative(path)}: #{text[0, 160]}")
        @bus&.publish("fix_loop:restructure", path: relative(path), rule:, ok:, message: text[0, 300])
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
