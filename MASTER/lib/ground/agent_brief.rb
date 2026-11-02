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
        soul = YAML.safe_load_file(File.join(root, "MASTER", "data", "soul.yml"), aliases: true)
        authority = soul.fetch("authority_order").map { |row| row.fetch("id").to_s }.join(" > ")

        <<~TEXT
          pub4 session context. You work under MASTER's constitution. No hook refuses a tool call or a finish;
          the laws are yours to apply.

          Source authority (highest first): #{authority}.
          Soul owns global identity, preservation, source order and protected paths;
            laws.yml owns individual Law identities, statements and invariant-node order.
          laws.yml#law_catalogue owns per-Law execution policy; law_runtime.yml keeps scanner, veto,
            plugin and /fix runtime configuration. law/ and checks/ implement and verify the Laws.
          Never let an autonomous repair rewrite soul.yml or laws.yml. Write straight to main;
            commit path-scoped (git commit -- <paths>), never -a.
          Commits take MASTER's shape (MASTER/data/commit_format.yml): a capitalised subject of at most #{limit}
            characters with no type prefix and no full stop, a blank line, a body saying what changed and what it
            cost, a blank line, and a Co-authored-by trailer.

          At the start of every task, run ruby MASTER/tools/agent_context.rb --json and consume
            conduct, blocking_rules, coverage, task_contract_schema and capabilities. For broad or
            cross-tree work, add --tree. Before the first write, retrieve each applicable Law with
            MASTER/bin/operator laws <ID>, then inspect its laws.yml#law_catalogue entry, its
            Law.define implementation and proof fixtures. Read law_runtime.yml only when the task
            changes scanner, veto, plugin or /fix runtime configuration.
            Before finishing, MASTER/bin/operator lint --changed-lines <files> shows what a changed
            line breaks; record any unrun check as NOT_RUN or INCONCLUSIVE, never PASS.
        TEXT
      end

      def laws_block(root)
        rows = top_laws(root)
        return [] if rows.empty?

        ["Governing invariant Laws (laws.yml document order):",
         *rows.map { |index, id, text| law_line(index:, id:, text:) }]
      end

      def law_line(index:, id:, text:) = "  #{index}. #{id}: #{text[0, STATEMENT_CHARS]}"

      def top_laws(root)
        # Plain YAML: the SessionStart hook loads this file alone, before MASTER boots.
        catalog = YAML.safe_load_file(File.join(root, "MASTER", "data", "laws.yml"), aliases: true) || {}
        catalog.filter_map do |id, row|
          next unless row.is_a?(Hash) && row["node"] && !row["statement"].to_s.empty?

          [catalog.keys.take_while { |key| key != id }.count { |key| catalog[key].is_a?(Hash) && catalog[key]["node"] } + 1,
           id.to_s, row["statement"].to_s.strip.gsub(/\s+/, " ")]
        end.first(TOP)
      end
    end
  end
end
