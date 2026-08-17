# frozen_string_literal: true

require "open3"
require "set"

module Master
  module CLI
    class Propose
      module CandidateSources
        private

        def from_violations
          return [] if @violations.zero?
          weight = high_violation_weight(@violations)
          [prop(action: "/polish", reason: "#{@violations} unresolved violation(s)", weight:, kind: :violation)]
        end

        def high_violation_weight(count)
          HIGH_VIOLATION_BASE_WEIGHT + [count / HIGH_VIOLATION_SCALE, HIGH_VIOLATION_BONUS_CAP].min
        end

        def from_last_assistant
          last = @session.messages.last
          return [] unless last && last[:role] == :assistant
          text = last[:content].to_s
          LAST_ASSISTANT_PROPOSALS.filter_map do |pattern, action, reason, weight|
            prop(action:, reason:, weight:) if text.match?(pattern)
          end
        end

        def from_git
          dirty = @git.dirty_count
          return [] if dirty.zero?
          [prop(action: "/commit", reason: "#{dirty} uncommitted file(s)", weight: 0.5 + [dirty / 40.0, 0.3].min)]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_git", event_bus: @bus)
          []
        end

        def from_phase
          case @session.phase.to_s
          when "discover" then [prop(action: "/through --dry-run", reason: "discover phase — survey state", weight: 0.4)]
          when "implement" then [prop(action: "/status", reason: "implement phase — check the tree", weight: 0.45)]
          when "audit" then [prop(action: "/through", reason: "audit phase — full pass", weight: 0.5)]
          else []
          end
        end

        def from_idle
          last = @session.messages.last
          return [] unless last
          ts = message_timestamp(last)
          timestamp = coerce_time(ts)
          return [] unless timestamp

          age = (Time.now - timestamp).to_i
          return [] if age < IDLE_SUGGESTION_AGE_SECONDS
          [prop(action: "/status", reason: "idle #{age / 60} min — check the tree", weight: 0.3 + [age / 7200.0, 0.2].min)]
        end

        def coerce_time(value)
          return value if value.is_a?(Time)

          Time.at(value.to_i)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CandidateSources.coerce_time")
          nil
        end

        def message_timestamp(message)
          message[:ts] || message[:timestamp]
        end

        def meaningful_words(text)
          text.downcase.scan(/[a-z][a-z0-9_]{2,}/).reject do |word|
            %w[the and for with from that this have into more less save context start fresh should what are you trying accomplish].include?(word)
          end.uniq
        end

        def current_axiom_names
          Master.load_yaml(Master::RULES_PATH).fetch("principle_priorities", {})
                .values.flatten.filter_map { |entry| entry.is_a?(Hash) ? entry.keys.first.to_s : nil }.to_set
        end

        def module_bucket(path)
          rel = path.to_s.delete_prefix("MASTER/lib/")
          parts = rel.split("/")
          return "" if parts.empty?

          parts.take(2).join("/")
        end

        def commit_line_deltas(path)
          out, status = Master::Io::Exec.capture3("git", "-C", @root, "log", "-3", "--numstat", "--format=", "--", path)
          return [] unless status.success?

          out.lines.filter_map do |line|
            next unless line.match?(/\A\d+\t\d+\t/)

            adds, dels, _file = line.split("\t", 3)
            adds.to_i + dels.to_i
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CandidateSources.commit_line_deltas")
          []
        end

        def from_bus_tail
          return [] unless @bus.respond_to?(:tail)
          events = begin
            @bus.tail(20)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Propose.from_bus_tail")
            []
          end
          return [] if events.empty?
          out = []
          escalations = events.count { |e| e[:event].to_s.include?("escalation") }
          out << prop(action: "/status", reason: "#{escalations} model escalation(s) recently", weight: 0.55) if escalations >= 2
          errors = events.count { |e| e[:event].to_s.match?(/error|fail/) }
          out << prop(action: "/doctor", reason: "#{errors} error event(s) on bus", weight: 0.6) if errors >= 3
          out
        end

        def from_topic_drift
          topic = @session.respond_to?(:topic) ? @session.topic.to_s.strip : ""
          return [] if topic.empty?
          return [] if @session.messages.size < 8

          overlap = topic_drift_overlap(topic)
          return [] unless overlap && overlap < 0.25

          [prop(
            action: "should I save context and start fresh?",
            reason: "conversation keywords drifted away from current task `#{topic}`; save context before switching domains",
            weight: 0.57,
          )]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_topic_drift", event_bus: @bus)
          []
        end

        def topic_drift_overlap(topic)
          topic_words = meaningful_words(topic)
          return if topic_words.empty?

          recent_users = @session.messages.last(8).select { |msg| msg[:role].to_s == "user" }.map { |msg| msg[:content].to_s }
          recent_words = meaningful_words(recent_users.join(" "))
          return if recent_words.empty?

          (topic_words & recent_words).size.to_f / [topic_words.size, 1].max
        end

        def from_benchmark
          return [] unless @scanner
          return [] unless @bus.respond_to?(:tail)

          rule_id = benchmark_candidate_rule_id
          return [] unless rule_id

          [prop(
            action: "/smoke",
            reason: "recent fix `#{rule_id}` touched a performance smell; run bin/smoke to verify the improvement holds",
            weight: 0.68,
          )]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_benchmark", event_bus: @bus)
          []
        end

        def benchmark_candidate_rule_id
          event = @bus.tail(30).reverse.find { |entry| entry[:event].to_s == "rule_loop:fix_applied" }
          return unless event

          rule_id = event[:payload].to_h[:rule].to_s
          return if rule_id.empty?

          rule = @scanner.rules.find { |candidate| candidate.id.to_s == rule_id }
          return unless rule

          tags = Array(rule.rule_tags).map { |tag| tag.to_s.upcase }
          hint = rule.description.to_s.downcase
          performanceish = tags.include?("PERFORMANCE") || rule_id.match?(/N_PLUS_ONE|SLOW|CACHE|LATENCY|THROUGHPUT/) ||
                            hint.match?(/performance|slow|latency|throughput|benchmark|smoke/)
          performanceish ? rule_id : nil
        end

        def from_entropy_radar
          return [] unless @bus.respond_to?(:tail)

          hot = entropy_hotspot
          return [] unless hot

          module_name, total = hot
          [prop(
            action: "/through",
            reason: "#{module_name} accumulated #{total} violation(s) across 3 recent scans; architectural attention needed",
            weight: 0.67,
          )]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_entropy_radar", event_bus: @bus)
          []
        end

        def entropy_hotspot
          scans = @bus.tail(100).select { |entry| entry[:event].to_s == "scan:complete" }
          return if scans.size < 3

          grouped = scans.last(3).group_by { |entry| module_bucket(entry[:payload].to_h[:path].to_s) }
          grouped.filter_map do |module_name, entries|
            next if module_name.empty? || entries.size < 3

            total = entries.sum { |entry| entry[:payload].to_h[:count].to_i }
            next if total <= ENTROPY_HOTSPOT_MIN_COUNT

            [module_name, total]
          end.max_by { |_, total| total }
        end

        def from_soul_evolution
          return [] unless @bus.respond_to?(:tail)

          new_patterns = soul_evolution_candidates
          return [] unless new_patterns

          [prop(
            action: "/through",
            reason: "#{new_patterns.first(3).join(', ')} surfaced repeatedly but are not in soul.yml; consider adding a constitutional axiom",
            weight: 0.64,
          )]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_soul_evolution", event_bus: @bus)
          []
        end

        def soul_evolution_candidates
          scan_events = @bus.tail(100).select { |entry| entry[:event].to_s == "scan:complete" }.last(5)
          return if scan_events.empty?

          surfaced = scan_events.flat_map { |entry| Array(entry[:payload].to_h[:top_rules]).map(&:to_s) }.uniq
          return if surfaced.size < 3

          known = current_axiom_names
          new_patterns = surfaced.reject { |rule| known.include?(rule) }
          new_patterns.size < 3 ? nil : new_patterns
        end

        def from_god_class_trajectory
          hot = god_class_hotspot
          return [] unless hot

          rel, total = hot
          [prop(
            action: "/through",
            reason: "#{rel} has grown by #{total} lines across 3 recent commits; warn before it crosses the god_class threshold",
            weight: 0.66,
          )]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_god_class_trajectory", event_bus: @bus)
          []
        end

        def god_class_hotspot
          candidates = Dir.glob(File.join(@root, "MASTER", "lib", "**", "*.rb")).first(20)
          candidates.filter_map do |path|
            next unless File.file?(path)

            deltas = commit_line_deltas(path)
            next unless deltas.size >= 3 && deltas.all? { |delta| delta > GOD_CLASS_HOTSPOT_MIN_DELTA }

            [path.delete_prefix("#{@root}/"), deltas.sum]
          end.max_by { |_, total| total }
        end

        def from_decoupling
          return [] unless @bus.respond_to?(:tail)

          pair = decoupling_pair
          return [] unless pair

          [prop(
            action: "/refactor",
            reason: "LAW_OF_DEMETER keeps firing between #{pair.join(' and ')}; propose an interface or adapter to cut the back-and-forth",
            weight: 0.69,
          )]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "propose.from_decoupling", event_bus: @bus)
          []
        end

        def decoupling_pair
          fixes = @bus.tail(100).select do |entry|
            entry[:event].to_s == "rule_loop:fix_applied" && entry[:payload].to_h[:rule].to_s == "LAW_OF_DEMETER"
          end
          return if fixes.size < 2

          modules = fixes.map { |entry| File.dirname(entry[:payload].to_h[:file].to_s) }.reject(&:empty?)
          return if modules.size < 2

          pair = modules.first(2)
          pair.uniq.size < 2 ? nil : pair
        end
      end
    end
  end
end
