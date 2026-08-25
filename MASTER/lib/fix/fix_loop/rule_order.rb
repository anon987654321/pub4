# frozen_string_literal: true

require_relative "../priority"
require_relative "../../ground/law_resolver"

module Master
  module Fix
    class FixLoop
      class RuleOrder
        TIER2_QUALITY_RULE_IDS = %w[DRY KISS SRP].freeze
        DEPS_PATH = File.join(Master::ROOT, "data", "rule_deps.yml").freeze
        PRIORS_PATH = File.join(Master::ROOT, "data", "patterns.yml").freeze
        AGE_PATH = File.join("data", "violation_age.yml").freeze
        SKIP_DIRS_RE = %r{/(\.git|vendor|tmp|var|node_modules|\.bundle|coverage|log|dist|knowledge)/}.freeze

        def initialize(rules:, learnings:, bus:, root:)
          @rules = rules
          @learnings = learnings
          @bus = bus
          @root = root
        end

        def ordered(violation_counts:)
          deps = load_deps
          priors = load_priors
          ext_wts = extension_weights
          law_resolver = Master::Ground::LawResolver.new
          rules_index = Priority.rules_index(root: @root)
          sorted = @rules.each_with_index.sort_by do |r, i|
            base_prior = priors.dig(r.id, "prior_p").to_f
            modifiers = priors.dig(r.id, "language_modifiers") || {}
            adjusted = ext_wts.sum { |ext, w| base_prior * (modifiers[ext] || 1.0) * w }
            frequency = violation_counts[r.id].to_f + adjusted
            quality = @learnings&.fix_quality(rule: r.id) || 0.5
            # tier2 stays a strict lexicographic primary key, not folded into
            # score()'s additive bonus: a high-frequency generic rule's score
            # can exceed a rare tier2 rule's +50 bonus, which would silently
            # break the "tier2 quality rules always come first" guarantee
            # test_fix_loop_priorities.rb depends on. score() still computes
            # law- and quality-aware ranking for everything else.
            score = Priority.score(
              rule_id: r.id, severity: rule_severity(r), frequency:,
              age_days: violation_age_days(r.id), law_resolver:, rules_index:, quality:
            )
            [tier2?(r.id) ? 0 : 1, -score, i]
          end.map(&:first)
          topo_sort(sorted, deps)
        end

        def dependency_levels(rules)
          deps = load_deps
          remaining = rules.map(&:id).to_set
          id_map = rules.to_h { |r| [r.id, r] }
          levels = []
          until remaining.empty?
            ready = remaining.select { |id| Array(deps[id]).none? { |dep| remaining.include?(dep) } }
            ready = [remaining.first] if ready.empty?
            levels << ready.filter_map { |id| id_map[id] }
            ready.each { |id| remaining.delete(id) }
          end
          levels
        end

        def tier2?(rule_id)
          TIER2_QUALITY_RULE_IDS.include?(rule_id.to_s)
        end

        private

        def rule_severity(rule)
          rule.respond_to?(:severity) ? rule.severity : :warning
        end

        def violation_age_days(rule_id)
          age = load_age[rule_id.to_s]
          return age.to_f if age

          0.0
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

        def extension_weights
          counts = Hash.new(0)
          Dir.glob(File.join(@root, "**", "*"))
            .select { |f| File.file?(f) && !f.match?(SKIP_DIRS_RE) }
            .each do |f|
              ext = File.extname(f).delete(".").downcase
              counts[ext] += 1 unless ext.empty?
            end
          total = counts.values.sum.to_f
          return {} if total.zero?
          counts.transform_values { |n| n / total }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.extension_weights", event_bus: @bus)
          {}
        end

        def load_deps
          @deps_cache ||=
            begin
              data = Master.load_yaml(DEPS_PATH)
              (data&.dig("deps") || {}).transform_values { |v| Array(v["after"] || []) }
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "fix_loop.load_deps", event_bus: @bus)
              {}
            end
        end

        def load_priors
          @priors_cache ||=
            begin
              (Master.load_yaml(PRIORS_PATH) || {})["violation_priors"] || {}
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "fix_loop.load_priors", event_bus: @bus)
              {}
            end
        end

        def load_age
          @age_cache ||=
            begin
              Master.load_yaml(File.join(@root, AGE_PATH)) || {}
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "fix_loop.load_age", event_bus: @bus)
              {}
            end
        end
      end
    end
  end
end
