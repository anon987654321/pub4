# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      HELP_TOPICS = {
        "run" => {
          summary: "natural-language task entry point",
          detail: ["/run <task>", "Routes intent through the pipeline and chooses the handler."]
        },
        "scan" => {
          summary: "deep-scan files or directories",
          detail: ["/scan [--dry-run] [profile] [path]", "Profiles: quick, full, axioms_only, solid_focus, critical. Use --profile NAME for explicit selection. Dry-run reports findings without changes."]
        },
        "self" => {
          summary: "scan MASTER itself",
          detail: ["/self", "Runs the MASTER self-scan with stream output."]
        },
        "fix" => {
          summary: "run or preview fixes for a target",
          detail: ["/fix [path]", "/fix --dry-run [path]", "/fix preview [path]", "Background control lives under /watch on|off|status."]
        },
        "status" => {
          summary: "show one-frame service and repo health",
          detail: ["/status", "Shows service state, git divergence, fix loop state, bundle status, and recent events."]
        },
        "resync" => {
          summary: "repair local divergence from origin/main",
          detail: ["/resync [--dry-run]", "Tags current HEAD, fetches, then resets and restarts unless dry-run is set."]
        },
        "tail" => {
          summary: "show recent event log lines",
          detail: ["/tail [N] [pattern]", "Filters runtime event JSONL by count and optional pattern."]
        },
        "why" => {
          summary: "explain a law, rule, anti-pattern, or style key",
          detail: ["/why <law|scan_rule|anti_pattern|style.key>"]
        },
        "propose" => {
          summary: "show next-action proposals",
          detail: ["/propose", "Ranks likely next actions from session, git, phase, and violation signals."]
        },
        "rules" => {
          summary: "list registered scan rules",
          detail: ["/rules list", "Shows rule IDs, severity, and implementation class."]
        },
        "triad" => {
          summary: "scan, preview fix, and review",
          detail: ["/triad <path>", "Runs scan, fix dry-run, and review for the same target."]
        },
        "rollback" => {
          summary: "revert the last recorded change",
          detail: ["/rollback", "Uses the undo stack; pipeline failure rollback remains automatic."]
        },
        "audit" => {
          summary: "show changed files this session",
          detail: ["/audit", "Lists git diff line counts for changed files."]
        },
        "grep" => {
          summary: "search session history",
          detail: ["/grep <pattern>", "Returns matching user/master turns from the current session."]
        },
        "watch" => {
          summary: "control background watching",
          detail: ["/watch on", "/watch off", "/watch status"]
        },
        "help" => {
          summary: "show command summaries or details",
          detail: ["/help", "/help <command>"]
        }
      }.freeze

      def help_text(command = nil)
        key = command.to_s.strip.sub(/\A\//, "")
        return help_summary if key.empty?

        topic = HELP_TOPICS[key]
        return "help: unknown command /#{key}" unless topic

        (["/#{key} - #{topic[:summary]}"] + topic[:detail]).join("\n")
      end

      def help_summary
        lines = HELP_TOPICS.map { |cmd, topic| "/#{cmd} - #{topic[:summary]}" }
        (lines + ["/help <command> - show details"]).join("\n")
      end
    end
  end
end
