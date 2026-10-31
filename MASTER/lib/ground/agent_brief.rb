# frozen_string_literal: true

require "yaml"
require_relative "commit_format"

module Master
  module Ground
    # What an agent is told before its first edit, whichever agent it is. A harness (a SessionStart hook,
    # a generated AGENTS.md, `bin/operator brief`) only calls this, so the text, the ranked laws and the
    # commit shape come from one place. It needs YAML and nothing else, so a hook runs it unbooted.
    module AgentBrief
      TOP = 12
      STATEMENT_CHARS = 110

      module_function

      def render(root:)
        [briefing(root), *laws_block(root)].join("\n")
      end

      def briefing(root)
        limit = CommitFormat.max_chars(root: File.join(root, "MASTER"))

        <<~TEXT
          pub4 session context. You work under MASTER's constitution. No hook refuses a tool call or a finish;
          the laws are yours to apply.

          Authority: MASTER/data/soul.yml > MASTER/data/laws.yml > MASTER/law/*.rb and scan/laws/*.rb
            > the agent contract (CLAUDE.md or AGENTS.md) > the tree contract.
          Never edit soul.yml or laws.yml. Write straight to main; commit path-scoped (git commit -- <paths>), never -a.
          Commits take MASTER's shape (MASTER/data/commit_format.yml): a capitalised subject of at most #{limit}
            characters with no type prefix and no full stop, a blank line, a body saying what changed and what it
            cost, a blank line, and a Co-authored-by trailer.

          Before the first write, read the law (ruby MASTER/tools/agent_context.rb --tree, then each Law with
            MASTER/bin/operator laws <ID>); before you finish, MASTER/bin/operator lint --changed-lines <files>
            shows what a line you changed breaks.
        TEXT
      end

      def laws_block(root)
        rows = top_laws(root)
        return [] if rows.empty?

        ["Highest-ranked laws now:", *rows.map { |priority, id, text| law_line(priority:, id:, text:) }]
      end

      def law_line(priority:, id:, text:) = "  #{id} (#{priority}): #{text[0, STATEMENT_CHARS]}"

      def top_laws(root)
        # Plain YAML, not Master.load_yaml: the SessionStart hook loads this file alone, and without the
        # runtime every session's briefing came back "no briefing (NoMethodError)".
        catalog = YAML.safe_load_file(File.join(root, "MASTER", "data", "laws.yml"), aliases: true) || {}
        rows = catalog.filter_map do |id, row|
          next unless row.is_a?(Hash) && row["priority"].is_a?(Numeric) && !row["statement"].to_s.empty?

          [row["priority"], id.to_s, row["statement"].to_s.strip.gsub(/\s+/, " ")]
        end
        rows.sort.first(TOP)
      end
    end
  end
end
