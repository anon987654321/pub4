# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # /rules — the corpus, one line each, because the instruction every agent
      # is given is to read the law before writing, and the only way to do that
      # was a YAML one-liner in CLAUDE.md that iterated the wrong shape for months.
      #
      # A list, not a copy: it reads data/rules.yml at call time, the same file
      # `bin/operator rules <ID>` prints a card from. An argument filters by id or
      # name, so `/rules guard` narrows to the rules that govern guard clauses.
      #
      # Read-only on purpose. The verb that enforces them is /review, and that
      # needs --apply to write. A second verb that scans and fixes would be the
      # same pipeline under another name.
      def dispatch_rules(root, ctx: nil)
        filter = arg_for(ctx).downcase
        return dispatch_rule_sources(root) if filter == "sources"

        rules = Master.law("rules") || []
        rows = rules.select do |rule|
          next true if filter.empty?

          "#{rule["id"]} #{rule["name"]}".downcase.include?(filter)
        end
        return "rules: nothing matches #{filter.inspect} in #{rules.size} declared" if rows.empty?

        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?

        lines = rows.map do |rule|
          kind = rule_enforcement(::Law.rules[rule["id"].to_s.to_sym])
          format("%-28s %-10s %-8s %s", rule["id"], rule["tier"], rule["severity"], kind)
        end
        ["#{rows.size} of #{rules.size} rules — bin/operator rules <ID> for one in full", *lines].join("\n")
      end

      def dispatch_rule_sources(root)
        audit = Master::Review::Scan::RuleRegistryAudit.new(root:).call
        drift = audit.source_drift

        [
          "rules: source drift",
          "  yaml_only: #{drift[:yaml_only].size}",
          *drift[:yaml_only].map { |id| "    #{id}" },
          "  law_only: #{drift[:law_only].size}",
          *drift[:law_only].map { |id| "    #{id}" },
          "  registry_only: #{drift[:registry_only].size}",
          *drift[:registry_only].map { |id| "    #{id}" },
        ].join("
")
      rescue StandardError => e
        "rules0: source audit failed — #{e.class}: #{e.message}"
      end

      # A rule absent from law/ is enforced by a scan detector in the registry;
      # a law/ rule with no detect, ask or practice block is declared only.
      def rule_enforcement(law)
        return "detector" unless law

        kind = [("detector" if law.detect), ("semantic" if law.ask), ("practice" if law.practice)].compact.join("+")
        kind.empty? ? "declared" : kind
      end

      # /why — one rule explained from law/ and data/rules.yml, and from the
      # model only when nothing local matches.
      def dispatch_why(agent:, root:, ctx: nil)
        rule = arg_for(ctx)
        return "usage: /why <law|scan_rule|anti_pattern|style.key>" if rule.empty?
        local = Trace::WhyExplainer.new(root:).explain(rule)
        return local if local
        agent.ask_once(Voice::Personality.why_prompt(rule))
      end
    end
  end
end
