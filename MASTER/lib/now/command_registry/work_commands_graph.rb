# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      def dispatch_graph(root:, code_index:, reference_graph:, ctx: nil)
        arg = arg_for(ctx)
        return "graph: usage: /graph <file>" if arg.empty?

        abs = expand_or_root(arg, root)
        return "graph: not found: #{arg}" unless File.file?(abs)

        data = gather_graph_data(abs, root:, code_index:, reference_graph:)
        render_graph_lines(abs.delete_prefix("#{root}/"), data).join("\n")
      rescue StandardError => e
        "graph: #{e.message}"
      end

      def gather_graph_data(abs, root:, code_index:, reference_graph:)
        reference_graph.build if reference_graph&.nodes&.empty?
        radius = reference_graph.blast_radius(abs)
        neighbors = Judge::GraphRetriever.new(reference_graph: reference_graph, root: root)
                                           .neighbors([abs], hops: 2, limit: 10)
        symbols = code_index ? code_index.symbols_in(abs) : []
        { radius:, neighbors:, symbols: }
      end

      def render_graph_lines(rel, data)
        radius, neighbors, symbols = data[:radius], data[:neighbors], data[:symbols]
        lines = ["graph #{rel}", "  inbound (#{radius[:inbound].size}): #{radius[:inbound].first(6).join(", ")}"]
        lines << "  outbound (#{radius[:outbound].size}): #{radius[:outbound].first(6).join(", ")}"
        lines << "  neighbors (#{neighbors.size}): #{neighbors.join(", ")}" if neighbors.any?
        symbol_line = symbols.first(8).map { |sym| "#{sym.fqn}:#{sym.line}" }.join(", ")
        lines << "  symbols (#{symbols.size}): #{symbol_line}" unless symbols.empty?
        lines
      end
    end
  end
end
