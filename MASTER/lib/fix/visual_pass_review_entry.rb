# frozen_string_literal: true

require_relative "visual_pass"

module Master
  module Fix
    # Public doors for the read-only `bin/operator visual review`. VisualPass
    # keeps its capture and critique steps private because /fix drives them
    # through #run; the review drives the same steps one at a time, so it can
    # stop after capture, skip the model, and print every pick. Composition
    # over copy: each method forwards to the private step /fix itself uses.
    module VisualPassReviewEntry
      # Points the pass at the review's output folder and gives the ghost stack
      # its own history root, so a review never adds a frame to /fix's history.
      def review_open(dir:, ghost_root:)
        FileUtils.mkdir_p(dir)
        @dir = dir
        @ghost_stack = VisualGhostStack.new(root: ghost_root, dir:)
        self
      end

      def review_surfaces(target:) = selected_surfaces(target:, pass: 1)

      def review_capture(surfaces) = capture_surfaces(surfaces, pass: 1)

      def review_decorate(captures) = decorate_design(captures)

      def review_sources(target:, captures:, graph:) = candidate_sources(target:, files: [], captures:, graph:)

      def review_critique(captures, sources, anchors, graph:) = run_critique(captures, sources, anchors, graph:)

      # The finding a pick anchors to, or nil; logged through FixTrace like /fix.
      def review_pick(pick, sources, anchors)
        FixTrace.pick(pick, finding_for(pick, sources, anchors), sources, anchors)
      end

      def review_graph = RailsVisualGraph.new(root: repo_root).build

      def review_sheet(captures) = VisualContactSheet.new(dir: @dir, root: repo_root).render(captures)
    end

    VisualPass.include(VisualPassReviewEntry)
  end
end
