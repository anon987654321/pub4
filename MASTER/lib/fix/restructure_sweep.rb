# frozen_string_literal: true

require "digest"
require_relative "restructure"
require_relative "restructure_sweep/context"
require_relative "restructure_sweep/contracts"

module Master
  module Fix
    # After /fix's repair passes, looks back over the tree for the structural
    # findings the per-file loop hands to a person (a file or class to split,
    # a tiny file to merge, a one-file directory to flatten) and restructures a
    # few of them: the model proposes the files to write and delete, a second
    # and hostile turn attacks the applied diff, and Restructure keeps the
    # change only if the proof holds. Smallest moves first, so a run spends its
    # budget where a restructure is likeliest to be sound.
    #
    # MASTER_FIX_RESTRUCTURES=0 switches it off; MASTER_FIX_RESTRUCTURE_ATTEMPTS
    # caps the findings tried per run, each costing two model calls.
    class RestructureSweep
      ATTEMPTS = Integer(ENV.fetch("MASTER_FIX_RESTRUCTURE_ATTEMPTS", 4))
      ROUNDS = Integer(ENV.fetch("MASTER_FIX_RESTRUCTURE_ROUNDS", 4))
      KEEPS = 3
      ORDER = %w[PARALLEL_HIERARCHY CYCLIC_DEPENDENCY FILE_SPRAWL NO_GOD_CLASS SMALL_FILES JS_MODULE_SIZE].freeze
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

        Any combination of these is allowed: split a file or class into cohesive
        parts; merge a tiny file into its owner; flatten a one-file directory;
        gather related code that has scattered across files; decouple a class from
        another's internals. Behaviour must not change.

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

      def initialize(agent:, repo_root:, bus: nil, restructure: nil)
        @agent = agent
        @root = repo_root
        @bus = bus
        @restructures = Hash.new { |cache, tree| cache[tree] = restructure || Restructure.new(repo_root:, tree:) }
      end

      def run(target:, run_id:)
        return [] if ENV["MASTER_FIX_RESTRUCTURES"] == "0" || !TREES.include?(File.basename(target.to_s))

        kept = []
        ROUNDS.times do |round|
          round_kept = []
          candidates(target, "#{run_id}-#{round}").first(ATTEMPTS).each do |finding|
            break if kept.size + round_kept.size >= KEEPS * ROUNDS

            result = attempt(finding)
            round_kept << result.value! if result&.ok?
          end
          kept.concat(round_kept)
          break if round_kept.empty?

          Master::Trace::Dmesg.status("restructure0", "round #{round + 1}, kept #{round_kept.size}, total #{kept.size}")
        end
        kept
      end

      # [path, rule, message] for each structural finding, smallest moves first;
      # within a rule the order rotates by run, so every finding comes up.
      def candidates(target, run_id)
        found = Context.structural_findings(target)
        seed = Digest::SHA256.hexdigest(run_id.to_s)[0, 8].to_i(16)
        ORDER.flat_map do |rule|
          group = found.select { |_path, id, _message| id == rule }
          group.empty? ? [] : group.rotate(seed % group.size)
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
        format(PROPOSE, contracts: Contracts.for(tree).strip, rule:, path: relative(path), message:,
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
