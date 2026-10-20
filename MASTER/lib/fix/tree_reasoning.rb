# frozen_string_literal: true

require "fileutils"
require "json"
require "set"
require_relative "tree"
require_relative "tree_proposals"
require_relative "tree_view"

module Master
  module Fix

    # The model's first read of the target: the Tree, and what it would change about the
    # shape of it. Its proposals are hints for the structural step that follows, never
    # edits. A proposal that names a path the tree does not hold is dropped, because a
    # model that invents a path has not read the tree.
    class TreeReasoning
      MAX_PROMPT_BYTES = 24_000

      Result = Data.define(:state, :summary, :proposals, :dropped) do
        def answered? = state == :answered
      end

      # Where the proposals are kept for the rest of the run. Reflection reads them back
      # to ask whether the shape the first read objected to was dealt with.
      def self.hints_path(root) = File.join(File.expand_path(root), ".master", "fix_tree_hints.json")

      def self.hints(root)
        path = hints_path(root)
        return [] unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "TreeReasoning.hints")
        []
      end

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = File.expand_path(root)
        @bus = bus
      end

      def call(target:)
        return result(:unavailable, "tree reasoning skipped, no model") unless @agent.class.method_defined?(:ask)

        tree = Tree.new(root: @root, target:)
        return result(:empty, "tree has no tracked files") if tree.files.empty?

        proposals, dropped = TreeProposals.parse(@agent.ask(prompt(tree), operation: :tree).to_s, tree.paths)
        record(tree:, proposals:, dropped:)
      rescue StandardError => e
        @bus&.publish("fix_loop:tree_error", target: target.to_s, error: "#{e.class}: #{e.message}")
        result(:inconclusive, "tree reasoning inconclusive, #{e.class}")
      end

      private

      def prompt(tree)
        text = <<~PROMPT
          First read of a MASTER /fix run, before any Law has scanned a line.

          Below is the tracked file tree of the target with its sprawl measurements. Say what
          you would change about the SHAPE of it: files that belong together, folders that earn
          nothing, names that mislead, a concern fused into one file. Reason from the tree and
          the measurements only. Do not claim a caller, a test or a line you cannot see here.
          Prefer folding into an existing owner over adding a file. Return nothing for a tree
          that is already shaped well.

          Return at most #{TreeProposals::MAX} lines, each exactly:
          PROPOSE: <#{TreeProposals::KINDS.join("|")}> | <path>[, <path>...] | <LAW_ID or NONE> | <one-sentence reason>

          Every path must appear in the tree below. Directories end the line with their name,
          files appear in the sprawl lists or under their directory.

          Measurements: #{JSON.generate(tree.metrics)}

          Tree:
          #{TreeView.new(tree).render}
        PROMPT
        text.byteslice(0, MAX_PROMPT_BYTES)
      end

      def record(tree:, proposals:, dropped:)
        path = self.class.hints_path(@root)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(proposals.map(&:to_h)))
        summary = summary(tree:, proposals:, dropped:)
        @bus&.publish("fix_loop:tree", metrics: tree.metrics, proposals: proposals.map(&:to_h), dropped:)
        Master::Trace::Dmesg.status("tree0", summary)
        Result.new(state: :answered, summary:, proposals:, dropped:)
      end

      def summary(tree:, proposals:, dropped:)
        metrics = tree.metrics
        note = dropped.positive? ? ", #{dropped} dropped for naming an unknown path" : ""
        "#{metrics[:files]} files in #{metrics[:directories]} dirs, #{proposals.size} proposal(s)#{note}"
      end

      def result(state, summary)
        Result.new(state:, summary:, proposals: [], dropped: 0)
      end
    end
  end
end
