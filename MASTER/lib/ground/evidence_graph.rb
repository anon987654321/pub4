# frozen_string_literal: true

module Master
  module Ground
    # Directed graph of evidence edges derived from ClusterRegistry.
    # Nodes: cluster ids. Edges:
    #   cluster -> file  (cluster covers this file)
    #   cluster -> signal (cluster emits/consumes this signal)
    #   cluster -> cluster (shared file or signal)
    #
    # Primary queries:
    #   clusters_for_file(path)  — which clusters reference a given path
    #   files_for(id)            — files a cluster covers
    #   signals_for(id)          — signals a cluster emits/consumes
    #   related(id, depth:)      — clusters reachable via shared edges
    class EvidenceGraph
      Edge = Data.define(:from, :to, :kind)

      def initialize(registry = ClusterRegistry.new)
        @registry = registry
        @file_index = Hash.new { |h, k| h[k] = [] }
        @signal_index = Hash.new { |h, k| h[k] = [] }
        @edges = []
        build
      end

      def clusters_for_file(path)
        normalize = path.to_s.delete_prefix("/")
        @file_index.each_with_object([]) do |(file, ids), acc|
          acc.concat(ids) if file.end_with?(normalize) || normalize.end_with?(file)
        end.uniq.filter_map { |id| @registry.find(id) }
      end

      def files_for(id)
        @edges.select { |e| e.from == id.to_s && e.kind == :file }.map(&:to)
      end

      def signals_for(id)
        @edges.select { |e| e.from == id.to_s && e.kind == :signal }.map(&:to)
      end

      def related(id, depth: 1)
        visited = Set.new([id.to_s])
        frontier = [id.to_s]
        depth.times do
          next_frontier = []
          frontier.each do |cid|
            shared_via_files(cid).each do |neighbor|
              next if visited.include?(neighbor)
              visited.add(neighbor)
              next_frontier << neighbor
            end
          end
          frontier = next_frontier
          break if frontier.empty?
        end
        visited.delete(id.to_s)
        visited.filter_map { |cid| @registry.find(cid) }
      end

      def edge_count = @edges.size
      def node_count = @registry.all.size

      private

      def build
        @registry.all.each do |entry|
          extract_files(entry).each do |file|
            @edges << Edge.new(from: entry.id, to: file, kind: :file)
            @file_index[file] << entry.id
          end
          extract_signals(entry).each do |signal|
            @edges << Edge.new(from: entry.id, to: signal, kind: :signal)
            @signal_index[signal] << entry.id
          end
        end
      end

      def extract_files(entry)
        raw = entry.raw
        [
          *Array(raw["files"]),
          *Array(raw["master_hooks"]).map { |h| h.to_s.split("#").first }
        ].uniq.reject(&:empty?)
      end

      def extract_signals(entry)
        Array(entry.raw["signals"]).map(&:to_s).reject(&:empty?)
      end

      def shared_via_files(cluster_id)
        files_for(cluster_id).flat_map { |f| @file_index[f] }.uniq - [cluster_id]
      end
    end
  end
end
