# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Audits rules.yml declarative corpus vs Ruby scanner registry.
      class RuleRegistryAudit
        Report = Data.define(:yaml_rules, :registry_ids, :kernel_ids, :lexical_wired, :lexical_unwired,
                             :semantic_only, :structural_unwired, :dep_graph_gaps, :mechanical) do
          # "clean" over 99 rules and "clean" over 225 are different claims, and
          # until now they printed identically everywhere except rake constitution.
          #
          # Counted, never subtracted. `yaml_rules - semantic_only.size` treats the
          # two populations as a partition and they are not: 22 rules carry a
          # semantic prompt beside a law or registry detector, and 14 design blocks
          # carry no detector at all. The subtraction claimed both halves as running
          # without a model, so this sentence read 107 here and 115 from
          # tools/rule_reach.rb, which the sentence itself sends the reader to.
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
          )
        end

        # One statement of "something can run this rule", because three gate
        # banners and tools/rule_reach.rb all print a count of it and three
        # separate spellings of the question gave two answers.
        #
        # `folded_into` names the rule that reports for this one: the id survives
        # so principle_map can trace it, and the detector exists once, elsewhere.
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
        rescue StandardError
          Set.new
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
          yaml_ids = yaml_entries.map { |r| r["id"].to_s.downcase }
          kernel = yaml_entries.select { |r| r["tier"] == "kernel" }.map { |r| r["id"].to_s.downcase }

          lexical_yaml = yaml_entries.select { |r| r["detect_lexical"] }
          lexical_wired = lexical_yaml.select { |r| registry.include?(r["id"].to_s.downcase) }
          lexical_unwired = lexical_yaml.reject { |r| registry.include?(r["id"].to_s.downcase) }

          semantic_only = yaml_entries.select { |r| r["detect_semantic"] && !r["detect_lexical"] && !r["detect_structural"] }
          structural_unwired = yaml_entries.select { |r| r["detect_structural"] && !registry.include?(r["id"].to_s.downcase) }

          {
            yaml_ids:, kernel:,
            lexical_wired: lexical_wired.map { |r| r["id"] },
            lexical_unwired: lexical_unwired.map { |r| r["id"] },
            semantic_only: semantic_only.map { |r| r["id"] },
            structural_unwired: structural_unwired.map { |r| r["id"] }
          }
        end
      end
    end
  end
end
