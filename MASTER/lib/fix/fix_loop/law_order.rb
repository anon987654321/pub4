# frozen_string_literal: true

require_relative "../priority"
require_relative "../../ground/law_resolver"

module Master
  module Fix
    class FixLoop
      class LawOrder
        # These are scanner ids, not law names. DRY/KISS/SRP never shipped as
        # Rule#id values, so tier2? was false for every rule and the primary
        # key was constant. NO_GOD_CLASS is SIMPLEST_WORKS, FEATURE_ENVY is
        # the SRP detector, FEW_ARGUMENTS is the conciseness one.
        TIER2_QUALITY_LAW_IDS = %w[NO_GOD_CLASS FEATURE_ENVY FEW_ARGUMENTS].freeze
        PRIORS_PATH = File.join(Master::ROOT, "data", "laws.yml").freeze
        AGE_PATH = File.join("data", "violation_age.yml").freeze
        SKIP_DIRS_RE = %r{/(\.git|vendor|tmp|var|node_modules|\.bundle|coverage|log|dist|knowledge)/}.freeze

        def initialize(laws:, learnings:, bus:, root:)
          @laws = laws
          @learnings = learnings
          @bus = bus
          @root = root
        end

        def ordered(violation_counts:)
          deps = load_deps
          law_resolver = Master::Ground::LawResolver.new
          rules_index = Priority.rules_index(root: @root)
          sorted = @laws.each_with_index.sort_by do |r, i|
            frequency = violation_counts[r.id].to_f
            quality = @learnings&.fix_quality(law: r.id) || 0.5
            # tier2 stays a strict lexicographic primary key, not folded into
            # score()'s additive bonus: a high-frequency generic rule's score
            # can exceed a rare tier2 rule's +50 bonus, which would silently
            # break the "tier2 quality rules always come first" guarantee
            # test_fix_loop_priorities.rb depends on. score() still computes
            # law- and quality-aware ranking for everything else.
            score = Priority.score(
              law_id: r.id, severity: law_severity(r), frequency:,
              age_days: law_age_days(r.id), law_resolver:, rules_index:, quality:
            )
            [tier2?(r.id) ? 0 : 1, -score, i]
          end.map(&:first)
          topo_sort(sorted, deps)
        end

        def dependency_levels(laws)
          deps = load_deps
          remaining = laws.map(&:id).to_set
          id_map = laws.to_h { |law| [law.id, law] }
          levels = []
          until remaining.empty?
            ready = remaining.select { |id| Array(deps[id]).none? { |dep| remaining.include?(dep) } }
            ready = [remaining.first] if ready.empty?
            levels << ready.filter_map { |id| id_map[id] }
            ready.each { |id| remaining.delete(id) }
          end
          levels
        end

        def tier2?(law_id)
          TIER2_QUALITY_RULE_IDS.include?(rule_id.to_s)
        end

        private

        def law_severity(law)
          law.respond_to?(:severity) ? law.severity : :warning
        end

        def law_age_days(law_id)
          age = load_age[law_id.to_s]
          return age.to_f if age

          0.0
        end

        def topo_sort(laws, deps)
          id_map = laws.to_h { |r| [r.id, r] }
          in_deg = Hash.new(0)
          adj = Hash.new { |h, k| h[k] = [] }
          laws.each do |law|
            (deps[law.id] || []).each do |dep_id|
              next unless id_map[dep_id]
              adj[dep_id] << law.id
              in_deg[law.id] += 1
            end
          end
          queue = laws.select { |law| in_deg[law.id].zero? }.map(&:id)
          sorted = []
          until queue.empty?
            id = queue.shift
            sorted << id_map[id]
            adj[id].each { |nxt| in_deg[nxt] -= 1; queue << nxt if in_deg[nxt].zero? }
          end
          sorted + (laws - sorted)
        end

        def load_deps
          @deps_cache ||= begin
            raw = Master.law("law_deps")
            raise "law_deps registry unreadable" unless raw.is_a?(Hash)

            raw.transform_values { |v| Array(v["after"] || []) }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.load_deps", event_bus: @bus)
          raise "fix_loop: law dependencies unreadable: #{e.class}: #{e.message}"
        end

        def load_age
          @age_cache ||= begin
            path = File.join(@root, AGE_PATH)
            File.file?(path) ? (Master.load_yaml(path) || {}) : {}
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "fix_loop.load_age", event_bus: @bus)
            raise "fix_loop: violation age unreadable: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
