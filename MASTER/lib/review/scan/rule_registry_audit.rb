# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Audits rules.yml declarative corpus vs Ruby scanner registry.
      class RuleRegistryAudit
        Report = Data.define(:yaml_rules, :registry_ids, :kernel_ids, :lexical_wired, :lexical_unwired,
                             :semantic_only, :structural_unwired, :dep_graph_gaps, :mechanical, :source_drift) do
          # "clean" over 99 rules and "clean" over 225 are different claims, and
          # until now they printed identically everywhere except rake constitution.
          #
          # Counted, never subtracted. A rule may be semantic-only, mechanical-only,
          # or layered and therefore belong to both populations. The audit reports
          # those populations independently so a semantic layer can never disappear
          # merely because its catalogue representation changed.
          def coverage_line = "#{mechanical.size} of #{yaml_rules} rules run without a model " \
                              "(see rake lint:rule_reach for what the rest need)"

          # The share of declared law that something can run. self_test.rb fails
          # below 35 and rules.yml self_test names the threshold.
          #
          # The weighted average that stood here averaged registry coverage against
          # a term reading `(wired + unwired) * 100 / (wired + unwired)` — 100.0 for
          # every possible corpus — so the score floored at 55.0 and the gate below
          # 35 could not fail whatever the tree did.
          def adherence_pct
            return 100.0 if yaml_rules.zero?

            (mechanical.size * 100.0 / yaml_rules).round(1)
          end

        end

        def initialize(root: Master::ROOT)
          @root = root
        end

        def call
          yaml_entries = load_yaml_rules
          registry = build_registry_ids
          c = classify_yaml_entries(yaml_entries, registry)

          Report.new(
            yaml_rules: c[:yaml_ids].size,
            registry_ids: registry,
            kernel_ids: c[:kernel],
            lexical_wired: c[:lexical_wired],
            lexical_unwired: c[:lexical_unwired],
            semantic_only: c[:semantic_only],
            structural_unwired: c[:structural_unwired],
            dep_graph_gaps: ungraphed_rule_ids(registry),
            mechanical: mechanical(yaml_entries, registry:).map { |rule| rule["id"] },
            source_drift: source_drift(yaml_entries, registry),
          )
        end

        # One statement of "something can run this rule", because three gate
        # banners and lib/operator/rule_reach.rb all print a count of it and three
        # separate spellings of the question gave two answers.
        #
        # `folded_into` names the rule that reports for this one: the id survives
        # so principle_map can trace it, and the detector exists once, elsewhere.
        def source_drift(yaml_entries, registry)
          yaml_ids = yaml_entries.map { |rule| key_of(rule) }.to_set
          laws = law_ids
          registry_ids = registry.map(&:to_s).map(&:downcase).to_set

          yaml_only = yaml_entries.filter_map do |rule|
            id = key_of(rule)
            folded = rule["folded_into"].to_s.downcase
            next if laws.include?(id) || registry_ids.include?(id)
            next if !folded.empty? && (laws.include?(folded) || registry_ids.include?(folded))

            rule["id"]
          end

          {
            yaml_only: yaml_only.sort.freeze,
            law_only: (laws - yaml_ids).sort.freeze,
            registry_only: (registry_ids - yaml_ids).sort.freeze,
          }.freeze
        end

        def mechanical(entries, registry: build_registry_ids)
          laws = law_ids
          entries.select do |rule|
            rule["detect_lexical"] || rule["detect_structural"] ||
              detected?(laws, registry, rule["id"]) || detected?(laws, registry, rule["folded_into"])
          end
        end

        # `Rule.inherited` registers every subclass in the process, and a test
        # that defines one is in the same process. Measured: rule_deps.ungraphed
        # read 133 on its own and 135 under `rake test`, so a ratchet on it would
        # have been measuring the suite rather than the corpus.
        # TestScanRuleFalsePositives::RaisingRule is the shape.
        #
        # A class whose source cannot be located counts as shipped: over-
        # reporting a rule is safe, and silently dropping one is how a census
        # stops measuring.
        # Anchored at the start as well as after a slash: a file run as the main
        # script reports the path it was invoked with, so `ruby -Itest
        # test/test_x.rb` yields a relative `test/test_x.rb` that a leading-slash
        # pattern misses — and the exclusion then works everywhere except in the
        # one place the test for it runs.
        TEST_DEFINED = %r{(?:\A|/)(?:test|spec)/}

        def shipped?(klass)
          location = klass.name && Object.const_source_location(klass.name)&.first
          location.nil? || !location.match?(TEST_DEFINED)
        end

        def ungraphed_rule_ids(registry = nil)
          Review::Scan::RuleDSL
          registry ||= Review::Scan::Rule.registry
            .select { |klass| shipped?(klass) }
            .map { |klass| RuleFactory.build(klass, root: @root).id.to_s }
            .to_set
          registry = registry.map { |id| id.to_s.downcase }.to_set
          deps = Master.law("rule_deps", root: @root)
          graphed = deps.keys.map { |k| k.to_s.downcase }.to_set
          registry.reject { |id| graphed.include?(id) }.sort
        end

        private

        def executable_semantic_ids
          require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
          ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
          ::Law.rules.values.select(&:semantic?).map { |law| law.id.to_s.downcase }.to_set
        end

        def law_detector?(id)
          require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
          ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
          law = ::Law.rules[id.to_sym]
          law&.detect
        end

        def detected?(laws, registry, id)
          key = id.to_s.downcase
          !key.empty? && (laws.include?(key) || registry.include?(key))
        end

        # Asked of the loaded registry, not of the source text: law/prose.rb
        # generates its four rules from data/rules.yml, so a grep for a literal
        # `Law.define(:ID)` reads none of them.
        def law_ids
          require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
          ::Law.load_all(File.join(@root, "law")) if ::Law.rules.empty?
          ::Law.rules.keys.map { |id| id.to_s.downcase }.to_set
        rescue StandardError => e
          raise "rule registry law census failed: #{e.class}: #{e.message}"
        end

        def load_yaml_rules
          Master.flatten_rules(Master.load_rules(root: @root).fetch("rules", {}))
        end

        # The reference loads the rule files, and a class in a multi-class file is
        # invisible to Zeitwerk until it does: asked cold, the registry answered
        # 81 mechanical rules where a loaded one answers 115.
        def build_registry_ids
          Review::Scan::RuleDSL
          Review::Scan::Rule.registry
            .select { |klass| shipped?(klass) }
            .reject { |klass| RuleFactory.bridge_class?(klass) }
            .map { |klass| RuleFactory.build(klass, root: @root).id.to_s.downcase }
            .to_set
        end

        def classify_yaml_entries(yaml_entries, registry)
          lexical_wired, lexical_unwired = yaml_entries.select { |r| r["detect_lexical"] }
                                                       .partition { |r| registry.include?(key_of(r)) }
          semantic_laws = executable_semantic_ids
          semantic_only = yaml_entries.select do |r|
            semantic_laws.include?(key_of(r)) &&
              !r["detect_lexical"] &&
              !r["detect_structural"] &&
              !law_detector?(r["id"])
          end
          structural_unwired = yaml_entries.select { |r| r["detect_structural"] }
                                           .reject { |r| registry.include?(key_of(r)) }

          {
            yaml_ids: yaml_entries.map { |r| key_of(r) },
            kernel: yaml_entries.select { |r| r["tier"] == "kernel" }.map { |r| key_of(r) },
            lexical_wired: ids_of(lexical_wired), lexical_unwired: ids_of(lexical_unwired),
            semantic_only: ids_of(semantic_only), structural_unwired: ids_of(structural_unwired)
          }
        end

        # The registry is keyed by downcased id; the report keeps the id as declared.
        def key_of(rule) = rule["id"].to_s.downcase
        def ids_of(rules) = rules.map { |r| r["id"] }
      end
    end
  end
end
