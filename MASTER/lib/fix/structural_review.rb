# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "law_map_repair"
require_relative "tree"
require_relative "tree_proposals"
require_relative "tree_reasoning"
require_relative "tree_view"

module Master
  module Fix

    # The second read of a /fix run, after the tree and the trace and before any Law scans: a whole-target
    # review with fresh eyes. What stands out, what is odd, what is over- or under-engineered, what wants a
    # refactor or a do-over, and where the target does not hold to the Law catalogue. Findings are hints for
    # the structural step and the closing reflection, never edits. A finding that names a path the tree
    # does not hold is dropped, and one that cites a Law that does not exist loses the citation.
    # This and the first read are /fix's semantic reading above the file, two calls per target; a
    # further pass per subsystem was weighed and refused: it repeats this read at many more calls,
    # and per-file semantic reads already cover changed files and a rotating slice of the rest.
    class StructuralReview
      CATEGORIES = %w[stands_out odd over_engineered under_engineered refactor do_over adherence].freeze
      HEADER = "FINDING"
      MAX_PROMPT_BYTES = 28_000

      Result = Data.define(:state, :summary, :findings, :dropped) do
        def answered? = state == :answered
      end

      def self.findings_path(root) = File.join(File.expand_path(root), ".master", "fix_structural_review.json")

      def self.findings(root)
        path = findings_path(root)
        return [] unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "StructuralReview.findings")
        []
      end

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = File.expand_path(root)
        @bus = bus
      end

      def call(target:, persist: true, first_read_proposals: nil)
        return result(:unavailable, "structural review skipped, no model") unless @agent.class.method_defined?(:ask)

        tree = Tree.new(root: @root, target:)
        return result(:empty, "tree has no tracked files") if tree.files.empty?

        findings, dropped = parse(
          @agent.ask(prompt(tree, first_read_proposals:), operation: :structural_review).to_s, tree
        )
        record(tree:, findings:, dropped:, persist:)
      rescue StandardError => e
        @bus&.publish("fix_loop:structural_review_error", target: target.to_s, error: "#{e.class}: #{e.message}")
        result(:inconclusive, "structural review inconclusive, #{e.class}")
      end

      private

      def parse(answer, tree)
        TreeProposals.parse(answer, tree.paths, TreeProposals::Dialect.new(HEADER, CATEGORIES, known_laws))
      end

      def known_laws
        Master::Fix::LawMapRepair.executable_law_ids
      end

      def prompt(tree, first_read_proposals: nil)
        text = <<~PROMPT
          Second read of a MASTER /fix run, before any Law has scanned a line.

          Review the whole target with fresh eyes, from the tree and its measurements only. Say what
          stands out, what is odd, what is over-engineered (more machinery than the job needs), what is
          under-engineered (a thin spot the design claims to cover), what wants a refactor, what wants a
          do-over, and where the target does not hold to the Laws. Prefer reduction to addition. Do not
          claim a caller, a test or a line you cannot see here, and do not recommend a rewrite of what
          works: the constitutional core is to be protected, the surface around it is to be reduced.

          Return at most #{TreeProposals::MAX} lines, each exactly:
          #{HEADER}: <#{CATEGORIES.join("|")}> | <path>[, <path>...] | <LAW_ID or NONE> | <one-sentence reason>

          A LAW_ID must be one the target is held to. Every path must appear in the tree below.

          Constitutional Laws: #{constitution}

          First-read proposals: #{JSON.generate(first_read_proposals || TreeReasoning.hints(@root))}

          Measurements: #{JSON.generate(tree.metrics)}

          Tree:
          #{TreeView.new(tree).render}
        PROMPT
        text.byteslice(0, MAX_PROMPT_BYTES)
      end

      # The priority-ranked entries of laws.yml, as id and statement.
      def constitution
        ranked = Master.load_laws(root: @root).select { |_id, entry| entry.is_a?(Hash) && entry["priority"] }
        ranked.map { |id, entry| "#{id}: #{entry["statement"]}" }.join(" | ")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "StructuralReview.constitution")
        "unavailable"
      end

      def record(tree:, findings:, dropped:, persist: true)
        if persist
          path = self.class.findings_path(@root)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.generate(findings.map(&:to_h)))
          @bus&.publish("fix_loop:structural_review", findings: findings.map(&:to_h), dropped:)
        end
        note = dropped.positive? ? ", #{dropped} dropped" : ""
        summary = "#{tree.metrics[:files]} files, #{findings.size} finding(s)#{note}"

        Master::Trace::Dmesg.status("look0", summary)
        Result.new(state: :answered, summary:, findings:, dropped:)
      end

      def result(state, summary)
        Result.new(state:, summary:, findings: [], dropped: 0)
      end
    end
  end
end
