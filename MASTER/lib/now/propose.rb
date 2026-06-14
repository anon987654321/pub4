# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Now
    class Propose
      MAX_PROPOSALS = 5
      STALE_HOURS = 24
      LEDGER_PATH = "runtime/proposals.jsonl"
      TOKENS_PER_PROPOSAL = 450
      COST_PER_1K_TOKENS = 0.003
      HIGH_VIOLATION_BASE_WEIGHT = 0.9
      HIGH_VIOLATION_SCALE = 50.0
      HIGH_VIOLATION_BONUS_CAP = 0.1
      LAST_ASSISTANT_PROPOSALS = [
        [/violation[s]? found|need(s)? fixing|to fix/i, "/polish", "assistant flagged violations", 0.85],
        [/\bunchanged\b|\balready\b/i, "/undo", "assistant says nothing changed", 0.75],
        [/\bdiff\b|\bedit\b|\bpatch\b/i, "show the diff", "assistant referenced an edit/patch", 0.65],
        [/(error|fail|exception|crash)/i, "what went wrong?", "error/failure in last reply", 0.7],
        [/\b(routed|tier|escalat|chose|picked)\b/i, "/why", "decision/score worth inspecting", 0.6],
        [/\bshould we\b|\btradeoff\b|\beither\b/i, "/council", "constitutional question raised", 0.55],
        [/\b(applied|wrote|patched|edited)\b/i, "/commit", "patch landed, ready to commit", 0.8]
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

        def rank = confidence * impact
      end

      def initialize(container:)
        @session     = container[:session]
        @config      = container[:config]
        @root        = container.fetch(:root, Dir.pwd)
        @violations  = 0
        @bus         = container[:bus]
        @git         = container[:git] || Master::Reach::GitOperations.new(@root)
        @learnings   = container[:learnings]
      end

      attr_writer :violations

      def call
        expire_stale!
        candidates = []
        candidates.concat(from_violations)
        candidates.concat(from_last_assistant)
        candidates.concat(from_git)
        candidates.concat(from_phase)
        candidates.concat(from_idle)
        candidates.concat(from_bus_tail)
        candidates
          .group_by { |c| c[:action] }
          .map { |_, group| group.max_by { |c| c[:rank] } }
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
        if @learnings&.respond_to?(:record_event)
          @learnings.record_event(event_type: :proposal_rejected, dimension: action)
        elsif @learnings&.respond_to?(:record)
          @learnings.record(trigger: "proposal", strategy: action, outcome: :failed)
        end
        "proposal rejected: #{action}"
      end

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
        when "discover" then [prop(action: "/scan", reason: "discover phase — survey state", weight: 0.4)]
        when "implement" then [prop(action: "/diff", reason: "implement phase — review staging", weight: 0.45)]
        when "audit" then [prop(action: "/council", reason: "audit phase — convene council", weight: 0.5)]
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
        return [] if age < 600
        [prop(action: "/history", reason: "idle #{age / 60} min — review what happened", weight: 0.3 + [age / 7200.0, 0.2].min)]
      end

      def coerce_time(value)
        return value if value.is_a?(Time)

        Time.at(value.to_i)
      rescue StandardError
        nil
      end

      def message_timestamp(message)
        message[:ts] || message[:timestamp]
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
        out << prop(action: "/why", reason: "#{escalations} model escalation(s) recently", weight: 0.55) if escalations >= 2
        errors = events.count { |e| e[:event].to_s.match?(/error|fail/) }
        out << prop(action: "/dmesg", reason: "#{errors} error event(s) on bus", weight: 0.6) if errors >= 3
        out
      end

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
          estimated_cost: estimate_cost(estimated_tokens)
        )
      end

      def confidence_for(weight)
        [[weight.to_f, 0.1].max, 1.0].min
      end

      def impact_for(action, kind)
        base = kind == :violation ? 0.9 : 0.55
        case action
        when "/polish", "/commit" then [base + 0.1, 1.0].min
        when "/council", "/why" then base
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
          ignored: entries.count { |entry| entry["event"] == "expired" }
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
      rescue StandardError
        false
      end

      def append_ledger(event, payload = {})
        FileUtils.mkdir_p(File.dirname(ledger_path))
        data = { ts: Time.now.utc.iso8601, event: event.to_s }.merge(payload)
        File.open(ledger_path, "a") { |file| file.puts(JSON.generate(data)) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "propose.append_ledger", event_bus: @bus)
      end

      def ledger_entries
        return [] unless File.exist?(ledger_path)

        File.readlines(ledger_path, chomp: true).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      def ledger_path
        File.join(@root, LEDGER_PATH)
      end
    end
  end
end
