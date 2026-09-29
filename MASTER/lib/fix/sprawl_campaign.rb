# frozen_string_literal: true

require "digest"
require_relative "restructure"
require_relative "restructure_sweep"
require_relative "restructure_sweep/contracts"
require_relative "../operator/sprawl_census"

module Master
  module Fix
    # Repository-level structural consolidation for /fix. Ordinary repair is
    # file-shaped; this is tree-shaped. It gives the model one measured map of a
    # governed tree, lets it propose a bounded batch, attacks that batch, and
    # delegates the actual write/proof/commit to Restructure.
    class SprawlCampaign
      TREES = RestructureSweep::Contracts::BY_TREE.keys.freeze
      MAX_CANDIDATES = 32
      DEFAULT_ROUNDS = 4
      DEFAULT_FINDINGS = 12
      DEFAULT_KEEPS = 4

      PROPOSE = <<~TEXT
        Consolidate this governed tree. This is an architectural cleanup, not a
        style pass.

        The evidence below is measured from the current checkout. Use it to find
        obsolete, duplicated, fragmented, over-nested, or ownerless structure.
        Prefer deletion, merge, flatten, or relocation into an existing owner.
        Do not invent defects and do not move a file merely to make the count
        smaller.

        Autonomous rules:
        - production readers, load paths, constants, entrypoints, generated files,
          database history, installed-target mirrors, and sacred paths are evidence.
        - tests can reveal behavior but are not production callers.
        - preserve runtime behavior and each tree's native architecture.
        - one plan may touch at most 48 paths, 32 deletions and 24 writes.
        - every moved reader must be updated in the same plan.
        - do not alter MASTER/data/rules.yml or MASTER/data/soul.yml.
        - no operation may cross the tree boundary.
        - leave ambiguous or speculative candidates alone.

        Tree: %<tree>s

        Tree shape:
        %<shape>s

        Actionable evidence:
        %<findings>s

        Existing tree contract:
        %<contracts>s

        Answer exactly: KEEP
        or exactly this plan format, with complete file contents and no code fences:
        SUMMARY: <one line>
        === WRITE <repository-relative path>
        <complete file content>
        === DELETE <repository-relative path>
        === END
      TEXT

      ATTACK = <<~TEXT
        Attack this proposed structural consolidation in %<tree>s.

        Summary: %<summary>s

        Check every write and delete against the evidence. Look for changed
        behavior, broken readers, stale require/load paths, Zeitwerk mismatches,
        Rails load conventions, OpenBSD installed-target semantics, generated
        paths, ownership violations, and complexity that was merely moved.

        The plan is acceptable only if the resulting tree is materially more
        coherent and smaller in structural sprawl, while preserving behavior.

        Answer exactly one line:
        APPROVE
        or
        REJECT: <reason>
      TEXT

      def initialize(agent:, repo_root:, bus: nil)
        @agent = agent
        @root = repo_root
        @bus = bus
        @restructures = {}
      end

      def run(target:, run_id:)
        return [] if ENV["MASTER_FIX_SPRAWL"] == "0"

        tree_targets(target).flat_map do |tree, tree_root|
          run_tree(tree, tree_root, "#{run_id}-#{tree}")
        end
      end

      # Read-only structural campaign evidence for /fix preview. No model call,
      # no filesystem mutation and no Git operation beyond the census.
      def preview(target)
        tree_targets(target).to_h do |tree, _tree_root|
          shape = Operator::SprawlCensus.shape(tree, root: @root)
          [tree, shape.merge(candidates: shape.fetch(:members).first(MAX_CANDIDATES))]
        end
      end

      private

      def tree_targets(target)
        name = File.basename(File.expand_path(target.to_s))
        return [[name, File.expand_path(target.to_s)]] if TREES.include?(name)

        root = File.expand_path(target.to_s)
        return TREES.filter_map do |tree|
          path = File.join(root, tree)
          [tree, path] if File.directory?(path)
        end if root == File.expand_path(@root)

        first = root.delete_prefix("#{File.expand_path(@root)}/").split("/").first
        return [[first, File.join(@root, first)]] if TREES.include?(first)

        []
      end

      def run_tree(tree, tree_root, prefix)
        kept = []
        rounds.times do |round|
          before = Operator::SprawlCensus.shape(tree)
          findings = candidates(tree_root, before, prefix)
          break if findings.empty?

          answer = ask(format(PROPOSE, tree:, shape: render_shape(before), findings: render_findings(findings),
                              contracts: RestructureSweep::Contracts.for(tree).strip))
          next if answer.strip == "KEEP"

          plan = Restructure::Plan.parse(answer)
          next if plan.empty?

          after_gate = lambda do |diff|
            verdict = ask(format(ATTACK, tree:, summary: plan.summary))
            return "review: #{verdict.lines.first.to_s.strip[0, 200]}" unless verdict.start_with?("APPROVE")

            shape_improves?(tree, before)
          end
          result = restructure_for(tree).call(
            plan,
            message: campaign_message(tree, plan),
            review: after_gate,
          )
          next unless result.ok?

          kept << result.value!
          Master::Trace::Dmesg.status("sprawl0", "#{tree}: round #{round + 1}, kept #{plan.paths.size} path(s)")
        end
        kept.first(keeps * rounds)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.sprawl_campaign", tree:)
        []
      end

      def candidates(tree_root, shape, run_id)
        structural = RestructureSweep::Context.structural_findings(tree_root)
          .select { |_path, rule, _message, _related| actionable_rule?(rule) }
          .first(findings_limit)
        members = shape[:members].take(MAX_CANDIDATES).map do |member|
          path = File.join(@root, member.fetch(:path))
          [path, member.fetch(:rule), member.fetch(:message), member.fetch(:related, [])]
        end
        (members + structural).uniq { |row| [row[1], row[0]] }.sort_by do |row|
          [priority(row[1]), row[0].to_s]
        end.tap do |rows|
          seed = Digest::SHA256.hexdigest(run_id.to_s)[0, 8].to_i(16)
          rows.rotate!(rows.empty? ? 0 : seed % rows.size)
        end.first(MAX_CANDIDATES)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.sprawl_campaign.candidates", tree_root:)
        []
      end

      def rounds = [Integer(ENV.fetch("MASTER_FIX_SPRAWL_ROUNDS", DEFAULT_ROUNDS)), 12].min

      def findings_limit = [Integer(ENV.fetch("MASTER_FIX_SPRAWL_FINDINGS", DEFAULT_FINDINGS)), MAX_CANDIDATES].min

      def keeps = [Integer(ENV.fetch("MASTER_FIX_SPRAWL_KEEPS", DEFAULT_KEEPS)), 12].min

      def actionable_rule?(rule)
        %w[DEAD_SUBTREE PARALLEL_HIERARCHY CYCLIC_DEPENDENCY FILE_SPRAWL SMALL_FILES NO_GOD_CLASS].include?(rule.to_s)
      end

      def priority(rule)
        {
          "DEAD_FILE" => 0, "DEAD_SUBTREE" => 0, "DUPLICATE_CONTENT" => 1,
          "PARALLEL_HIERARCHY" => 2, "CYCLIC_DEPENDENCY" => 3, "FILE_SPRAWL" => 4,
          "LONE_DIRECTORY" => 5, "SMALL_FILES" => 6, "NO_GOD_CLASS" => 7
        }.fetch(rule.to_s, 99)
      end

      def render_shape(shape)
        shape.map do |key, value|
          next "#{key}: #{value}" unless value.is_a?(Array)

          "#{key}:\n" + value.first(MAX_CANDIDATES).map { |row| "  #{row[:path]} — #{row[:message]}" }.join("\n")
        end.compact.join("\n")
      end

      def render_findings(rows)
        rows.map do |path, rule, message, related|
          suffix = Array(related).first(8).map { |item| item.to_s.delete_prefix("#{@root}/") }.join(", ")
          "  #{path.to_s.delete_prefix("#{@root}/")} — #{rule}: #{message}#{suffix.empty? ? "" : " [related: #{suffix}]"}"
        end.join("\n")
      end

      def shape_improves?(tree, before)
        after = Operator::SprawlCensus.shape(tree)
        score(after) < score(before)
      end

      def score(shape)
        shape.fetch(:files) +
          (shape.fetch(:directories) * 2) +
          (shape.fetch(:lone_dirs) * 5) +
          (shape.fetch(:stutter) * 2) +
          (shape.fetch(:vague_names) * 2) +
          (shape.fetch(:duplicate_groups) * 4) +
          (shape.fetch(:deep_paths) * 3)
      end

      def restructure_for(tree)
        @restructures[tree] ||= Restructure.new(repo_root: @root, tree:)
      end

      def campaign_message(tree, plan)
        "refactor: #{plan.summary.empty? ? "consolidate #{tree}" : plan.summary}\n\n"           "Structural consolidation by /fix for #{tree}; measured shape improved, "           "hostile review approved the batch, and the tree-specific restructure proof held."
      end

      def ask(prompt)
        @agent.ask(prompt, operation: :sprawl_campaign).to_s.strip
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.sprawl_campaign.ask")
        ""
      end
    end
  end
end
