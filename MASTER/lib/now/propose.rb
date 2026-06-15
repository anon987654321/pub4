# frozen_string_literal: true

require "open3"

module Master
  module Now
    Proposal = Data.define(:action, :reason, :weight)

    class Propose
      MAX_PROPOSALS = 5
      STALE_HOURS = 24

      def initialize(container:)
        @session     = container[:session]
        @config      = container[:config]
        @root        = container.fetch(:root, Dir.pwd)
        @violations  = 0
        @bus         = container[:bus]
      end

      attr_writer :violations

      def call
        candidates = []
        candidates.concat(from_violations)
        candidates.concat(from_last_assistant)
        candidates.concat(from_git)
        candidates.concat(from_phase)
        candidates.concat(from_idle)
        candidates.concat(from_bus_tail)
        candidates
          .group_by { |c| c[:action] }
          .map { |_, group| group.max_by { |c| c[:weight] } }
          .sort_by { |c| -c[:weight] }
          .first(MAX_PROPOSALS)
      end

      def top
        call.first
      end

      private

      def from_violations
        return [] if @violations.zero?
        weight = 0.9 + [@violations / 50.0, 0.1].min
        [{ action: "/polish", reason: "#{@violations} unresolved violation(s)", weight: }]
      end

      ASSISTANT_PATTERNS = [
        [/violation[s]? found|need(s)? fixing|to fix/i, "/polish", "assistant flagged violations", 0.85],
        [/\bunchanged\b|\balready\b/i, "/undo", "assistant says nothing changed", 0.75],
        [/\bdiff\b|\bedit\b|\bpatch\b/i, "show the diff", "assistant referenced an edit/patch", 0.65],
        [/(error|fail|exception|crash)/i, "what went wrong?", "error/failure in last reply", 0.7],
        [/\b(routed|tier|escalat|chose|picked)\b/i, "/why", "decision/score worth inspecting", 0.6],
        [/\bshould we\b|\btradeoff\b|\beither\b/i, "/council", "constitutional question raised", 0.55],
        [/\b(applied|wrote|patched|edited)\b/i, "/commit", "patch landed, ready to commit", 0.8],
      ].freeze

      def from_last_assistant
        last = @session.messages.last
        return [] unless last && last[:role] == :assistant
        text = last[:content].to_s
        ASSISTANT_PATTERNS.filter_map do |pat, action, reason, weight|
          prop(action, reason, weight) if text.match?(pat)
        end
      end

      def from_git
        out, _, st = Open3.capture3("git", "-C", @root, "status", "--porcelain")
        return [] unless st.success?
        dirty = out.lines.size
        return [] if dirty.zero?
        [prop("/commit", "#{dirty} uncommitted file(s)", 0.5 + [dirty / 40.0, 0.3].min)]
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "propose.from_git", event_bus: @bus)
        []
      end

      def from_phase
        case @session.phase.to_s
        when "discover" then [prop("/scan", "discover phase — survey state", 0.4)]
        when "implement" then [prop("/diff", "implement phase — review staging", 0.45)]
        when "audit" then [prop("/council", "audit phase — convene council", 0.5)]
        else []
        end
      end

      def from_idle
        last = @session.messages.last
        return [] unless last
        ts = last.fetch(:ts) { last[:timestamp] }
        return [] unless ts
        age = Time.now.to_i - ts.to_i
        return [] if age < 600
        [prop("/history", "idle #{age / 60} min — review what happened", 0.3 + [age / 7200.0, 0.2].min)]
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
        out << prop("/why", "#{escalations} model escalation(s) recently", 0.55) if escalations >= 2
        errors = events.count { |e| e[:event].to_s.match?(/error|fail/) }
        out << prop("/dmesg", "#{errors} error event(s) on bus", 0.6) if errors >= 3
        out
      end

      def prop(action, reason, weight)
        Proposal.new(action:, reason:, weight:).to_h
      end
    end
  end
end
