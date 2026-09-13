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
      # `bin/operator rule <ID>` prints a card from. An argument filters by id or
      # name, so `/rules guard` narrows to the rules that govern guard clauses.
      #
      # Read-only on purpose. The verb that enforces them is /review, and that
      # needs --apply to write. A second verb that scans and fixes would be the
      # same pipeline under another name.
      def dispatch_rules(_root, ctx: nil)
        filter = arg_for(ctx).downcase
        rules = Master.law("rules") || []
        rows = rules.select do |rule|
          next true if filter.empty?

          "#{rule["id"]} #{rule["name"]}".downcase.include?(filter)
        end
        return "rules: nothing matches #{filter.inspect} in #{rules.size} declared" if rows.empty?

        lines = rows.map do |rule|
          kind = rule["detect_semantic"] ? "semantic" : "detector"
          format("%-28s %-10s %-8s %s", rule["id"], rule["tier"], rule["severity"], kind)
        end
        ["#{rows.size} of #{rules.size} rules — bin/operator rule <ID> for one in full", *lines].join("\n")
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
