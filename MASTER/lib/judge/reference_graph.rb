# frozen_string_literal: true

require "find"
require "set"

module Master
  module Judge
  # ReferenceGraph builds a lightweight semantic connectivity map
  # across the repository. This becomes the foundation for:
  # - safe rename
  # - precise rollback
  # - dead-file proof
  # - blast-radius estimation
  # - topology visualization
  # - governed autonomous restructuring
    class ReferenceGraph
      DEFAULT_EXTENSIONS = %w[
        .rb .js .ts .tsx .erb .yml .yaml .json .md .sh
      ].freeze

      IGNORE_DIRS = %w[
        .git node_modules vendor tmp log coverage dist build .bundle
      ].freeze

      Edge = Struct.new(:type, :from, :to, :weight, keyword_init: true)

      attr_reader :nodes, :edges

      def initialize(root:, event_bus: nil)
        @root = File.expand_path(root)
        @bus = event_bus
        @nodes = Set.new
        @edges = []
      end

      def build
        files.each do |file|
          analyze(file)
        end

        graph = {
          nodes: @nodes.to_a.sort,
          edges: @edges.map(&:to_h),
          metrics: metrics,
        }

        @bus&.publish(
          "reference_graph:built",
          nodes: graph[:nodes].size,
          edges: graph[:edges].size
        )

        graph
      end

      def blast_radius(path)
        rel = relative(path)
        impacted = @edges.select { |edge| edge.to == rel || edge.from == rel }
        {
          target: rel,
          inbound: impacted.select { |e| e.to == rel }.map(&:from).uniq.sort,
          outbound: impacted.select { |e| e.from == rel }.map(&:to).uniq.sort,
        }
      end

      private

      def files
        collected = []
        Find.find(@root) do |path|
          name = File.basename(path)

          if File.directory?(path)
            Find.prune if IGNORE_DIRS.include?(name)
            next
          end

          next unless DEFAULT_EXTENSIONS.include?(File.extname(path))

          collected << path
        end
        collected
      end

      def analyze(file)
        rel = relative(file)
        @nodes << rel

        content = File.read(file, encoding: "UTF-8", invalid: :replace, undef: :replace)

        ruby_requires(content, rel)
        constant_refs(content, rel)
        command_refs(content, rel)
        event_refs(content, rel)
      rescue StandardError => e
        Master::Ground::Swallow.log(
          e,
          context: "reference_graph.analyze",
          event_bus: @bus,
          path: rel
        )
      end

      def ruby_requires(content, rel)
        content.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten.each do |target|
          edge(from: rel, to: normalize_require(target), type: :require, weight: 1.0)
        end
      end

      def constant_refs(content, rel)
        content.scan(/\b([A-Z][A-Za-z0-9_:]{2,})\b/).flatten.tally.each do |constant, count|
          edge(from: rel, to: "const:#{constant}", type: :constant, weight: count)
        end
      end

      def command_refs(content, rel)
        content.scan(%r{/[a-z_]+}).flatten.tally.each do |command, count|
          edge(from: rel, to: "command:#{command}", type: :command, weight: count)
        end
      end

      def event_refs(content, rel)
        content.scan(/["']([a-z_]+:[a-z_]+)["']/).flatten.tally.each do |event, count|
          edge(from: rel, to: "event:#{event}", type: :event, weight: count)
        end
      end

      def normalize_require(target)
        cleaned = target.gsub("../", "")
        cleaned.end_with?(".rb") ? cleaned : "#{cleaned}.rb"
      end

      def edge(from:, to:, type:, weight:)
        @edges << Edge.new(
          type:,
          from:,
          to:,
          weight:
        )
      end

      def metrics
        grouped = @edges.group_by(&:type)
        {
          node_count: @nodes.size,
          edge_count: @edges.size,
          require_edges: grouped.fetch(:require, []).size,
          constant_edges: grouped.fetch(:constant, []).size,
          event_edges: grouped.fetch(:event, []).size,
          command_edges: grouped.fetch(:command, []).size,
        }
      end

      def relative(path)
        File.expand_path(path).sub(%r{\A#{Regexp.escape(@root)}/?}, "")
      end
    end
  end
end
