# frozen_string_literal: true

module Master
  module Judge
    # GraphRAG-style multi-hop, dependency-aware context selection over the in-memory
    # ReferenceGraph. Returns the changed files' dependency neighbours, ranked by proximity,
    # so the agent sees structurally-relevant context instead of flat-search hits.
    # Pure Ruby, no external store. Refs: RepoGraph (+32.8%); RANGER (arXiv:2509.25257).
    class GraphRetriever
      HOP_DECAY = 0.5

      def initialize(reference_graph:, root:)
        @graph = reference_graph
        @root = File.expand_path(root)
      end

      # Top neighbour files within `hops` of the seeds, ranked by proximity (decay per hop).
      def neighbors(seed_files, hops: 2, limit: 12)
        seeds = Array(seed_files).map { |file| File.expand_path(file, @root) }
        return [] if seeds.empty? || hops < 1

        scores = Hash.new(0.0)
        frontier = seeds
        hops.times { |depth| frontier = visit(frontier, scores: scores, decay: HOP_DECAY**depth, seeds: seeds) }
        ranked(scores, limit)
      end

      private

      def visit(frontier, scores:, decay:, seeds:)
        frontier.flat_map { |file| score_neighbours(file, scores: scores, decay: decay, seeds: seeds) }.uniq
      end

      def score_neighbours(file, scores:, decay:, seeds:)
        adjacent(file).filter_map do |rel|
          absolute = File.expand_path(rel, @root)
          next if seeds.include?(absolute)

          scores[rel] += decay
          absolute
        end
      end

      def adjacent(file)
        radius = @graph.blast_radius(file)
        Array(radius[:inbound]) + Array(radius[:outbound])
      rescue StandardError
        []
      end

      def ranked(scores, limit)
        scores.sort_by { |_path, score| -score }.first(limit).map { |path, _score| path }
      end
    end
  end
end
