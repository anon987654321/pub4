# frozen_string_literal: true

require "set"

module Master
  module Review
  # PageRank over the CodeIndex symbol-reference graph, budgeted to a
  # token window. Aider-style repo map. Files with many incoming references
  # rank higher; focus[] biases the random surfer toward chat-mentioned files.
  #
  # Wiring is left to the operator. Typical use:
  #   map = Master::Review::RepoMap.new(code_index: ai[:code_index], root: root)
  #   prompt_context << map.render(focus: [current_file])
    class RepoMap
      DEFAULT_TOKEN_BUDGET = 4096
      CHARS_PER_TOKEN = 4
      DAMPING = 0.85
      ITERATIONS = 30
      MAX_DEFS_PER_FILE = 20

      def initialize(code_index:, root:, token_budget: DEFAULT_TOKEN_BUDGET)
        @index = code_index
        @root = File.expand_path(root)
        @budget = token_budget
      end

      def render(focus: [])
        @index.wait_for_build unless @index.ready?
        g = build_graph
        ranks = pagerank(g, normalize(focus))
        ordered = ranks.sort_by { |_, r| -r }.map(&:first)
        pack(ordered)
      end

      private

      def normalize(focus)
        focus.map { |f| File.expand_path(f, @root) }.to_set
      end

      def build_graph
        symbols = @index.symbols
        owners = symbols.each_value.to_h { |s| [s.fqn, s.file] }
        edges = Hash.new { |h, k| h[k] = Set.new }
        @index.references.each do |ref|
          target = owners[ref.to_fqn]
          edges[ref.from_file] << target if target && target != ref.from_file
        end
        edges
      end

      def pagerank(g, focus)
        nodes = (g.keys | g.values.flat_map(&:to_a)).uniq
        return {} if nodes.empty?
        rank = seed(nodes, focus)
        ITERATIONS.times { rank = step(g:, nodes:, rank:, focus:) }
        rank
      end

      def seed(nodes, focus)
        base = focus.empty? ? 1.0 / nodes.size : 1.0 / focus.size
        nodes.to_h { |n| [n, focus.empty? || focus.include?(n) ? base : 0.0] }
      end

      def step(g:, nodes:, rank:, focus:)
        tele = teleport(nodes, focus)
        out = nodes.to_h { |n| [n, tele[n]] }
        nodes.each do |from|
          successors = g[from]
          next if successors.empty?
          share = DAMPING * rank[from] / successors.size
          successors.each { |to| out[to] += share }
        end
        out
      end

      def teleport(nodes, focus)
        if focus.empty?
          base = (1 - DAMPING) / nodes.size
          return nodes.to_h { |n| [n, base] }
        end

        base = (1 - DAMPING) / focus.size
        nodes.to_h { |n| [n, focus.include?(n) ? base : 0.0] }
      end

      def pack(ordered)
        sections = ["# Repo map", ""]
        tokens = estimate(sections.join("\n"))
        ordered.each do |path|
          block = format_file(path)
          next if block.empty?
          cost = estimate(block.join("\n"))
          break if tokens + cost > @budget
          sections.concat(block)
          tokens += cost
        end
        sections.join("\n")
      end

      def format_file(path)
        symbols = @index.symbols_in(path)
        return [] if symbols.empty?
        defs = symbols.first(MAX_DEFS_PER_FILE).map { |s| "  #{s.type}: #{s.fqn} (line #{s.line})" }
        ["## #{relative(path)}", *defs, ""]
      end

      def estimate(text)
        text.bytesize / CHARS_PER_TOKEN
      end

      def relative(path)
        path.sub("#{@root}/", "")
      end
    end
  end
end
