# frozen_string_literal: true

module Master
  module Loop
    # Subscribes to fix_loop:soul_proposal events and appends structured
    # proposals to runtime/soul_proposals.md for operator review.
    # Fires when a rule recurs 3+ consecutive fix passes without resolution.
    class SoulProposals
      PROPOSALS_PATH = "runtime/soul_proposals.md"

      def initialize(event_bus:, root: Master::ROOT)
        @bus  = event_bus
        @root = root
      end

      def attach
        @bus&.subscribe("fix_loop:soul_proposal") { |payload| record(payload) }
        self
      end

      private

      def record(payload)
        rule_id = payload[:rule] || payload["rule"]
        sample  = Array(payload[:sample] || payload["sample"])
        return unless rule_id

        append(format_proposal(rule_id, sample))
        @bus&.publish("soul:proposal_ready", rule: rule_id, path: PROPOSALS_PATH)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "soul_proposals.record", event_bus: @bus, rule_id:)
      end

      def format_proposal(rule_id, sample)
        files = sample.filter_map { |v| v[:file] || v["file"] }.uniq.first(3).join(", ")
        lines = sample.filter_map { |v| v[:line] || v["line"] }.first(3).join(", ")
        <<~MD
          ## #{rule_id} — #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}

          Rule `#{rule_id}` recurred 3+ consecutive fix passes without resolution.

          Files: #{files.empty? ? "unknown" : files}
          Lines: #{lines.empty? ? "unknown" : lines}

          Proposed actions:
          - Tighten the autofix for `#{rule_id}` in `lib/judge/scan/rules/`
          - Raise severity to block the loop until manually resolved
          - Add to `workflow.yml` autoloop `skip_rules` if it is a false positive

        MD
      end

      def append(proposal)
        path = File.join(@root, PROPOSALS_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") { |io| io.write(proposal) }
      rescue StandardError => e
        Ground::Swallow.log(e, context: "soul_proposals.append", event_bus: @bus)
      end
    end
  end
end
