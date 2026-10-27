# frozen_string_literal: true

require_relative "../priority"
require_relative "../../ground/law_resolver"

module Master
  module Fix
    class FixLoop
      class LawOrder
        # These are scanner ids, not law names. DRY/KISS/SRP never shipped as
        # Law#id values, so tier2? was false for every rule and the primary
        # key was constant. NO_GOD_CLASS is SIMPLEST_WORKS, FEATURE_ENVY is
        # the SRP detector, FEW_ARGUMENTS is the conciseness one.
        TIER2_QUALITY_LAW_IDS = %w[NO_GOD_CLASS FEATURE_ENVY FEW_ARGUMENTS].freeze
        # What a user meets first outranks what a reviewer reads. A JavaScript exception, a
        # route answering 4xx/5xx or a stylesheet that never arrives breaks the page; a
        # rendered defect makes it worse; a code law makes the source worse. The browser
        # checks found the first kind and /fix repaired a RuboCop line before any of them.
        IMPACT_TIERS = %i[runtime rendered code].freeze
        RUNTIME_EVIDENCE = Regexp.union(
          /uncaught JavaScript exception/i,
          /browser console error/i,
          /\bHTTP [45]\d\d\b/,
          /first-party (?:resource|executable request|request) failed/i,
          /network-error page/i,
          /broken asset|asset (?:missing|not found)/i,
        )
        RENDERED_LAW_IDS = %w[RENDERED_VISUAL_REFINEMENT SCALE_SNAP].freeze
        AGE_PATH = File.join("data", "violation_age.yml").freeze

        def initialize(laws:, learnings:, bus:, root:)
          @laws = laws
          @learnings = learnings
          @bus = bus
          @root = root
        end

        def ordered(violation_counts:)
          violation_counts ||= {}
          deps = load_deps
          law_resolver = Master::Ground::LawResolver.new
          laws_index = Priority.laws_index(root: @root)
          sorted = @laws.each_with_index.sort_by do |r, i|
            id = r.id
            frequency = violation_counts.fetch(id, 1).to_f
            quality = @learnings&.fix_quality(law: id) || 0.5
            # tier2 stays a strict lexicographic primary key, not folded into
            # score()'s additive bonus: a high-frequency generic rule's score
            # can exceed a rare tier2 rule's +50 bonus, which would silently
            # break the "tier2 quality laws always come first" guarantee
            # test_fix_loop_priorities.rb depends on. score() still computes
            # law- and quality-aware ranking for everything else.
            score = Priority.score(
              law_id: id, severity: law_severity(r), frequency:,
              age_days: law_age_days(id), law_resolver:, laws_index:, quality:
            )
            [law_impact(id), tier2?(id) ? 0 : 1, -score, i]
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
          TIER2_QUALITY_LAW_IDS.include?(law_id.to_s)
        end

        # A law's tier when all that is known is its id.
        def law_impact(law_id) = IMPACT_TIERS.index(RENDERED_LAW_IDS.include?(law_id.to_s) ? :rendered : :code)

        # A finding's tier, read from what it says: its evidence outranks its law, because
        # a console error filed under a rendered law is still a broken page.
        def self.impact(finding)
          row = finding.to_h.transform_keys(&:to_s)
          said = row["impact"].to_s
          evidence = "#{row["message"]} #{row["evidence"]}"
          return IMPACT_TIERS.index(:runtime) if said == "runtime" || evidence.match?(RUNTIME_EVIDENCE)

          rendered = said == "rendered" || RENDERED_LAW_IDS.include?(row["law"].to_s)
          IMPACT_TIERS.index(rendered ? :rendered : :code)
        end

        # The most urgent tier among a file's findings, for the worklist's first key.
        def self.file_impact(rows) = Array(rows).map { |row| impact(row) }.min || IMPACT_TIERS.index(:code)

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
          id_map = laws.to_h { |law| [law.id, law] }
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
