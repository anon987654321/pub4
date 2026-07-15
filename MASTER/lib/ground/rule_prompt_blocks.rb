# frozen_string_literal: true

module Master
  module Ground
    class Rules
      # Markdown block rendering for system-prompt injection — a rendering
      # concern separate from Rules' own lookup/parsing responsibility.
      module RulePromptBlocks
        def kernel_block
          return if kernel.empty?

          pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
          "## Kernel Rules (enforced)\n#{pairs}"
        end

        def philosophy_block(limit: 5)
          items = philosophy(limit:)
          return if items.empty?

          top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
          "## Rules (top #{items.size})\n#{top}"
        end
      end
    end
  end
end
