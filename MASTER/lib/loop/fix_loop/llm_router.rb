# frozen_string_literal: true

module Master
  module Loop
    class FixLoop
      # Routes violations to RuleLoop passes with dependency ordering (O103).
      class LlmRouter
        DEPS_PATH = File.join(Master::ROOT, "data", "rule_deps.yml").freeze
        PRIORS_PATH = File.join(Master::ROOT, "data", "violation_priors.yml").freeze
        TIER2_QUALITY_RULE_IDS = %w[DRY KISS SRP].freeze

        def initialize(rules:, agent:, scanner:, root:, bus: nil, learnings: nil, preamble: nil)
          @rules = rules
          @agent = agent
          @scanner = scanner
          @root = root
          @bus = bus
          @learnings = learnings
          @preamble = preamble
          @violation_counts = Hash.new(0)
        end

        attr_reader :violation_counts

        def llm_pass(violations:, files:, pass:, deadline: nil)
          fixed = 0
          ordered_rules.each do |rule|
            next unless violations.any? { |v| v[:rule] == rule.id }
            if deadline && Time.now >= deadline
              @bus&.publish("fix_loop:pass_timeout", pass:, rule_skipped: rule.id)
              break
            end
            if circuit_open?
              @bus&.publish("fix_loop:llm_skipped", pass:, rule_skipped: rule.id, reason: "circuit_open")
              break
            end
            rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root,
                              bus: @bus, learnings: @learnings)
            rl.injected_preamble = @preamble
            @bus&.publish("fix_loop:tier2_quality_route", pass:, rule: rule.id) if tier2_quality_rule?(rule.id)
            result = rl.run_once(files)
            @violation_counts[rule.id] += result[:fixed]
            fixed += result[:fixed]
            @bus&.publish("fix_loop:rule_result", pass:, rule: rule.id, **result)
          end
          fixed
        end

        def ordered_rules(collect_files:)
          deps = load_deps
          priors = load_priors
          ext_wts = extension_weights(collect_files)
          rules = @rules.sort_by do |r|
            base_prior = priors.dig(r.id, "prior_p").to_f
            modifiers = priors.dig(r.id, "language_modifiers") || {}
            adjusted = ext_wts.sum { |ext, w| base_prior * (modifiers[ext] || 1.0) * w }
            density = @violation_counts[r.id].to_f + adjusted
            quality = @learnings&.fix_quality(rule: r.id) || 0.5
            tier2_priority = tier2_quality_rule?(r.id) ? 1 : 0
            [-tier2_priority, -density, -quality]
          end
          topo_sort(rules, deps)
        end

        def circuit_open?
          breaker = @agent.respond_to?(:circuit_breaker) ? @agent.circuit_breaker : nil
          return false unless breaker.respond_to?(:open_models)
          !breaker.open_models.empty?
        rescue StandardError
          false
        end

        def open_breakers
          @agent.respond_to?(:circuit_breaker) ? Array(@agent.circuit_breaker&.open_models) : []
        rescue StandardError
          []
        end

        private

        def tier2_quality_rule?(rule_id)
          TIER2_QUALITY_RULE_IDS.include?(rule_id.to_s)
        end

        def extension_weights(collect_files)
          counts = Hash.new(0)
          collect_files.call(@root).each do |f|
            ext = File.extname(f).delete(".").downcase
            counts[ext] += 1 unless ext.empty?
          end
          total = counts.values.sum.to_f
          return {} if total.zero?
          counts.transform_values { |n| n / total }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.llm_router.extension_weights", event_bus: @bus)
          {}
        end

        def topo_sort(rules, deps)
          id_map = rules.to_h { |r| [r.id, r] }
          in_deg = Hash.new(0)
          adj = Hash.new { |h, k| h[k] = [] }
          rules.each do |rule|
            (deps[rule.id] || []).each do |dep_id|
              next unless id_map[dep_id]
              adj[dep_id] << rule.id
              in_deg[rule.id] += 1
            end
          end
          queue = rules.select { |r| in_deg[r.id].zero? }.map(&:id)
          sorted = []
          until queue.empty?
            id = queue.shift
            sorted << id_map[id]
            adj[id].each { |nxt| in_deg[nxt] -= 1; queue << nxt if in_deg[nxt].zero? }
          end
          sorted + (rules - sorted)
        end

        def load_deps
          data = Master.load_yaml(DEPS_PATH)
          (data&.dig("deps") || {}).transform_values { |v| Array(v["after"] || []) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.llm_router.load_deps", event_bus: @bus)
          {}
        end

        def load_priors
          Master.load_yaml(PRIORS_PATH) || {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.llm_router.load_priors", event_bus: @bus)
          {}
        end
      end
    end
  end
end