# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../ground/bias_guard"


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

module Master
  module CLI
    class Propose
      include CandidateSources

      MAX_PROPOSALS = 5
      STALE_HOURS = 24
      LEDGER_PATH = "runtime/proposals.jsonl"
      TOKENS_PER_PROPOSAL = 450
      COST_PER_1K_TOKENS = 0.003
      HIGH_VIOLATION_BASE_WEIGHT = 0.9
      HIGH_VIOLATION_SCALE = 50.0
      HIGH_VIOLATION_BONUS_CAP = 0.1
      IDLE_SUGGESTION_AGE_SECONDS = 600
      ENTROPY_HOTSPOT_MIN_COUNT = 10
      GOD_CLASS_HOTSPOT_MIN_DELTA = 20
      LAST_ASSISTANT_PROPOSALS = [
        [/violation[s]? found|need(s)? fixing|to fix/i, "/through", "assistant flagged violations", 0.85],
        [/\bunchanged\b|\balready\b/i, "/undo", "assistant says nothing changed", 0.75],
        [/\bdiff\b|\bedit\b|\bpatch\b/i, "show the diff", "assistant referenced an edit/patch", 0.65],
        [/(error|fail|exception|crash)/i, "what went wrong?", "error/failure in last reply", 0.7],
        [/\b(applied|wrote|patched|edited)\b/i, "/commit", "patch landed, ready to commit", 0.8],
      ].freeze

      class Proposal
        ATTRIBUTES = %i[
          action reason weight confidence impact kind estimated_tokens estimated_cost
        ].freeze

        attr_reader(*ATTRIBUTES)

        def initialize(action:, reason:, weight:, confidence:, impact:, kind:, estimated_tokens:, estimated_cost:)
          @action = action
          @reason = reason
          @weight = weight
          @confidence = confidence
          @impact = impact
          @kind = kind
          @estimated_tokens = estimated_tokens
          @estimated_cost = estimated_cost
        end

        def [](key)
          return rank if key.to_sym == :rank

          public_send(key)
        end

        def to_h
          ATTRIBUTES.to_h { |key| [key, public_send(key)] }.merge(rank:)
        end

        def rank
          confidence * impact
        end
      end

      def initialize(container:)
        @session = container[:session]
        @config = container[:config]
        @root = container.fetch(:root, Dir.pwd)
        @violations = 0
        @bus = container[:bus]
        @git = container.fetch(:git) { Master::Io::GitOperations.new(@root) }
        @learnings = container[:learnings]
      end

      attr_writer :violations

      def call
        expire_stale!
        finalize_candidates(collect_candidates)
      end

      def collect_candidates
        candidates = []
        candidates.concat(from_violations)
        candidates.concat(from_last_assistant)
        candidates.concat(from_git)
        candidates.concat(from_topic_drift)
        candidates.concat(from_benchmark)
        candidates.concat(from_entropy_radar)
        candidates.concat(from_soul_evolution)
        candidates.concat(from_god_class_trajectory)
        candidates.concat(from_decoupling)
        candidates.concat(from_phase)
        candidates.concat(from_idle)
        candidates.concat(from_bus_tail)
        candidates
      end

      def finalize_candidates(candidates)
        candidates
          .group_by { |c| c[:action] }
          .map { |_, group| group.max_by { |c| c[:rank] } }
          .map { |candidate| bias_guard.annotate(candidate) }
          .sort_by { |c| [-c[:rank], -c[:weight]] }
          .first(MAX_PROPOSALS)
      end

      def top
        call.first
      end

      def displayed(rows)
        Array(rows).each { |row| append_ledger(:displayed, proposal: row.to_h) }
      end

      def acted(action)
        append_ledger(:acted, action: action.to_s)
      end

      def reject(action)
        action = action.to_s.strip
        return "propose: reject requires an action" if action.empty?

        append_ledger(:rejected, action:)
        append_corrections_ledger(action)
        @bus&.publish("user_correction", action:, source: "proposal_rejected")
        if @learnings&.respond_to?(:record_event)
          @learnings.record_event(event_type: :proposal_rejected, dimension: action)
        elsif @learnings&.respond_to?(:record)
          @learnings.record(trigger: "proposal", strategy: action, outcome: :failed)
        end
        "proposal rejected: #{action}"
      end

      private

      def prop(action:, reason:, weight:, kind: :opportunity, impact: nil, confidence: nil)
        stats = proposal_stats(action)
        estimated_tokens = estimate_tokens(action)
        confidence_value = tuned_confidence(confidence || confidence_for(weight), stats)
        impact_value = tuned_impact(impact || impact_for(action, kind), stats)
        Proposal.new(
          action:,
          reason:,
          weight:,
          confidence: confidence_value,
          impact: impact_value,
          kind:,
          estimated_tokens:,
          estimated_cost: estimate_cost(estimated_tokens),
        )
      end

      def bias_guard
        @bias_guard ||= Master::Ground::BiasGuard.new(root: @root)
      end

      def confidence_for(weight)
        [[weight.to_f, 0.1].max, 1.0].min
      end

      def impact_for(action, kind)
        base = kind == :violation ? 0.9 : 0.55
        case action
        when "/polish", "/commit" then [base + 0.1, 1.0].min
        when "/review", "/why" then base
        else [base - 0.1, 0.1].max
        end
      end

      def estimate_tokens(action)
        multiplier = action.to_s.match?(%r{\A/(polish|council|scan)}) ? 2 : 1
        TOKENS_PER_PROPOSAL * multiplier
      end

      def estimate_cost(tokens)
        ((tokens / 1000.0) * COST_PER_1K_TOKENS).round(4)
      end

      def tuned_confidence(confidence, stats)
        bonus = stats[:acted] * 0.05
        penalty = stats[:rejected] * 0.1
        [[confidence + bonus - penalty, 0.1].max, 1.0].min
      end

      def tuned_impact(impact, stats)
        penalty = stats[:ignored] * 0.05
        [[impact - penalty, 0.1].max, 1.0].min
      end

      def proposal_stats(action)
        entries = ledger_entries.select { |entry| entry["action"] == action.to_s || entry.dig("proposal", "action") == action.to_s }
        {
          acted: entries.count { |entry| entry["event"] == "acted" },
          rejected: entries.count { |entry| entry["event"] == "rejected" },
          ignored: entries.count { |entry| entry["event"] == "expired" },
        }
      end

      def expire_stale!
        cutoff = Time.now - STALE_HOURS * 3600
        ledger_entries.select { |entry| entry["event"] == "displayed" }.each do |entry|
          next unless stale_display?(entry, cutoff)

          append_ledger(:expired, action: entry.dig("proposal", "action").to_s, displayed_at: entry["ts"])
        end
      end

      def stale_display?(entry, cutoff)
        action = entry.dig("proposal", "action").to_s
        ts = Time.parse(entry["ts"].to_s)
        return false if action.empty? || ts >= cutoff

        ledger_entries.none? do |candidate|
          candidate["action"] == action &&
            %w[acted rejected expired].include?(candidate["event"]) &&
            Time.parse(candidate["ts"].to_s) >= ts
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Propose.stale_display?")
        false
      end

      def append_ledger(event, payload = {})
        FileUtils.mkdir_p(File.dirname(ledger_path))
        data = { ts: Time.now.utc.iso8601, event: event.to_s }.merge(payload)
        File.open(ledger_path, "a") { |file| file.puts(JSON.generate(data)) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "propose.append_ledger", event_bus: @bus)
      end

      def append_corrections_ledger(action)
        path = File.join(@root, "runtime", "corrections.jsonl")
        FileUtils.mkdir_p(File.dirname(path))
        data = { ts: Time.now.utc.iso8601, action: action.to_s }
        File.open(path, "a") { |file| file.puts(JSON.generate(data)) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "propose.append_corrections_ledger", event_bus: @bus)
      end

      def ledger_entries
        return [] unless File.exist?(ledger_path)

        File.readlines(ledger_path, chomp: true).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Propose.ledger_entries")
          nil
        end
      end

      def ledger_path
        File.join(@root, LEDGER_PATH)
      end
    end
  end
end
