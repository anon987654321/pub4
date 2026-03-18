# frozen_string_literal: true

module Master
  module Tools
    # SymbolLookup — lets the LLM query the live codebase symbol graph.
    # Returns definition location, callers, and impact analysis for any symbol.
    class SymbolLookup
      NAME        = "symbol_lookup"
      DESCRIPTION = "Look up a Ruby class, module, or method in the codebase. " \
                    "Returns file, line, and all cross-file references (callers/usages). " \
                    "Use before refactoring to understand impact."

      def initialize(code_index:, event_bus: nil)
        @index = code_index
        @bus   = event_bus
      end

      def call(name:)
        return Result.err("symbol_lookup: index not built yet", category: :validation) unless @index.built?

        hits = @index.query(name)
        if hits.is_a?(Hash) && hits[:error]
          return Result.err("symbol_lookup: #{hits[:error]}", category: :validation)
        end

        @bus&.publish("tool:symbol_lookup", name:, hits: hits.size)
        Result.ok(hits.map { |h| format_hit(h) }.join("\n\n"))
      end

      private

      def format_hit(h)
        lines = ["#{h[:fqn]} (#{h[:type]})"]
        lines << "  defined: #{h[:file]}:#{h[:line]}"
        lines << "  parent:  #{h[:parent]}" if h[:parent] && h[:parent] != "Object"
        if h[:used_in].any?
          lines << "  used in:"
          h[:used_in].each { |ref| lines << "    #{ref}" }
        else
          lines << "  used in: (no cross-file references found)"
        end
        lines.join("\n")
      end
    end
  end
end
