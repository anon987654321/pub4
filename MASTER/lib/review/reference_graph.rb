# frozen_string_literal: true

require "find"
require "set"

module Master
  module Review
  # ReferenceGraph builds a lightweight semantic connectivity map
  # across the repository. This becomes the foundation for:
  # - safe rename
  # - precise rollback
  # - dead-file proof
  # - blast-radius estimation
  # - topology visualization
  # - governed autonomous restructuring
    class ReferenceGraph
      # Keep this graph aligned with FileCollector's eligible text corpus,
      # including extensionless build files, dotfiles, documentation and config.
      # Oversized or binary files are not source dependencies; /fix's inventory
      # reports their separate exclusion/blocking state.
      MAX_TEXT_BYTES = 2 * 1024 * 1024
      PROBE_BYTES = 8 * 1024

      IGNORE_DIRS = %w[
        .git node_modules vendor tmp log coverage dist build .bundle .cache
        .next .output .turbo reports root
      ].freeze

      Edge = Struct.new(:type, :from, :to, :weight, keyword_init: true)

      attr_reader :nodes, :edges, :analysis_failures, :root

      def initialize(root:, event_bus: nil)
        @root = File.expand_path(root)
        @bus = event_bus
        @nodes = Set.new
        @edges = []
        @analysis_failures = []
        @built = false
        @build_lock = Mutex.new
      end

      # One complete source read builds the graph before repair. Repeated callers
      # reuse it; an operator-requested /fix explicitly refreshes it so stale
      # references from a previous run cannot authorize an edit.
      def build(refresh: false)
        @build_lock.synchronize do
          if refresh || !@built
            @nodes.clear
            @edges.clear
            @analysis_failures.clear
            files.each { |file| analyze(file) }
            @built = true
          end

          graph = {
            nodes: @nodes.to_a.sort,
            edges: @edges.map(&:to_h),
            metrics:,
            analysis_failures: @analysis_failures.map(&:dup),
          }

          @bus&.publish(
            "reference_graph:built",
            nodes: graph[:nodes].size,
            edges: graph[:edges].size,
            analysis_failures: graph[:analysis_failures].size,
          )

          graph
        end
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

          next if File.symlink?(path)
          next unless text_file?(path)

          collected << path
        end
        collected
      end

      def text_file?(path)
        size = File.size(path)
        return false if size > MAX_TEXT_BYTES

        probe = File.binread(path, PROBE_BYTES)
        return false if probe.include?("\0")

        # Extensionless source and dotfiles are common authoritative inputs
        # (Rakefile, Gemfile, Makefile, .gitignore). Include all readable text
        # instead of quietly narrowing the dependency graph by suffix.
        probe.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      rescue SystemCallError
        false
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
        @analysis_failures << { path: rel.to_s, error: "#{e.class}: #{e.message}" }
        Master::Ground::Swallow.log(
          e,
          context: "reference_graph.analyze",
          event_bus: @bus,
          path: rel,
        )
      end

      def ruby_requires(content, rel)
        content.scan(/\b(require_relative|require)\s+["']([^"']+)["']/).each do |kind, target|
          to = if kind == "require_relative"
            resolve_relative_require(rel, target)
          else
            normalize_require(target)
          end
          edge(from: rel, to:, type: :require, weight: 1.0)
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

      def resolve_relative_require(rel, target)
        base = File.dirname(File.join(@root, rel))
        absolute = File.expand_path(target, base)
        relative = absolute.delete_prefix("#{@root}/")
        normalize_require(relative)
      end

      def normalize_require(target)
        cleaned = target.sub(%r{\A\./}, "")
        cleaned.end_with?(".rb") ? cleaned : "#{cleaned}.rb"
      end

      def edge(from:, to:, type:, weight:)
        @edges << Edge.new(
          type:,
          from:,
          to:,
          weight:,
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

      public :relative

      def includes_path?(path)
        @nodes.include?(relative(path))
      end
    end
  end
end
