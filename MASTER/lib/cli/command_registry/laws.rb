# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # /laws — the corpus, one line each, because the instruction every agent
      # is given is to read the law before writing, and the only way to do that
      # was a YAML one-liner in CLAUDE.md that iterated the wrong shape for months.
      #
      # A list, not a copy: it reads data/laws.yml at call time, the same file
      # `bin/operator laws <ID>` prints a card from. An argument filters by id or
      # name, so `/laws guard` narrows to the laws that govern guard clauses.
      #
      # Read-only on purpose. The verb that enforces them is /review, and that
      # needs --apply to write. A second verb that scans and fixes would be the
      # same pipeline under another name.
      def dispatch_rules(root, ctx: nil)
        filter = arg_for(ctx).downcase
        return dispatch_law_sources(root) if filter == "sources"
        return dispatch_law_index if filter == "index"

        laws = Master.law_entries(root:)
        rows = laws.select do |rule|
          next true if filter.empty?

          "#{rule["id"]} #{rule["name"]}".downcase.include?(filter)
        end
        return "laws: nothing matches #{filter.inspect} in #{laws.size} declared" if rows.empty?

        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

        lines = rows.map do |rule|
          kind = law_enforcement(::Law.definitions[rule["id"].to_s.to_sym])
          format("%-28s %-10s %-8s %s", rule["id"], rule["tier"], rule["severity"], kind)
        end
        ["#{rows.size} of #{laws.size} laws — bin/operator laws <ID> for one in full", *lines].join("\n")
      end

      def dispatch_law_index
        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
        rows = ::Law::Index.validate!
        lifecycle = rows.group_by { |row| row["lifecycle"] }.transform_values(&:size)
        proof = rows.group_by { |row| row["proof"] }.transform_values(&:size)
        universal = rows.count { |row| row["law_scope"] == "universal" }

        [
          "laws: executable index",
          "  laws: #{rows.size}",
          "  universal_principles: #{universal}",
          "  lifecycle: #{lifecycle.sort.map { |state, count| "#{state}=#{count}" }.join(", ")}",
          "  proof: #{proof.sort.map { |kind, count| "#{kind}=#{count}" }.join(", ")}",
          "  index: valid",
        ].join("\n")
      rescue StandardError => e
        "rules0: executable index failed — #{e.class}: #{e.message}"
      end

      def dispatch_law_sources(root)
        audit = Master::Review::Scan::LawRegistryAudit.new(root:).call
        drift = audit.source_drift

        [
          "laws: source drift",
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
      def law_enforcement(law)
        return "detector" unless law

        kind = [("detector" if law.detect), ("semantic" if law.ask), ("practice" if law.practice)].compact.join("+")
        kind.empty? ? "declared" : kind
      end

      # /why — one rule explained from law/ and data/laws.yml, and from the
      # model only when nothing local matches.
      def dispatch_why(agent:, root:, memory: nil, ctx: nil)
        rule = arg_for(ctx)
        return "usage: /why <law|path|scan_rule|anti_pattern|style.key>" if rule.empty?

        local = Trace::WhyExplainer.new(root:).explain(rule)
        answer = local || agent.ask_once(Voice::Personality.why_prompt(rule))
        receipt = Ground::BootReceipt.session(root:, agent:, memory:)
        return answer if receipt.empty?

        [answer, Ground::BootReceipt.session_line(receipt)].compact.join("\n")
      end
    end
  end
end
