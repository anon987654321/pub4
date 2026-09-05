# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      HELP_TOPICS = {
        "through" => {
          summary: "scan → fix → critique a path",
          detail: [
            "/through [path] — aesthetic scan, deep scan, fix, re-scan, critique.",
            "Or just say the path. Mechanical autofix writes on each file as it is",
            "scanned; --dry-run / --no-autofix preview without writing.",
          ],
        },
        "status" => {
          summary: "one-frame health",
          detail: ["/status — mode, git, fix loop, last pipeline stage, recent events."],
        },
        "undo" => {
          summary: "revert the last recorded change",
          detail: ["/undo — /rollback is the same."],
        },
        "commit" => {
          summary: "record the current diff",
          detail: [
            "/commit — git add -u and git commit. No confirmation flag.",
            "Path-scope from a worktree. Never run this on a shared checkout.",
          ],
        },
        "model" => {
          summary: "show or switch the active model",
          detail: ["/model", "/model <name> — routing from data/models.yml."],
        },
        "pair" => {
          summary: "issue or redeem a pairing code",
          detail: ["/pair issue [label]", "/pair <code>", "/pair status"],
        },
        "doctor" => {
          summary: "host, provider, and exposure health",
          detail: ["/doctor — keys, disk, git, pairing/gateway exposure."],
        },
        "help" => {
          summary: "this list",
          detail: ["/help", "/help <command>"],
        },
        "clear" => {
          summary: "clear the session transcript",
          detail: ["/clear — does not undo file changes."],
        },
        "why" => {
          summary: "what a rule says, and where it comes from",
          detail: ["/why <law|scan_rule|anti_pattern|style.key> — Trace::WhyExplainer looks it",
                   "up in law/ and data/rules.yml, and asks the model only when nothing matches."],
        },
      }.freeze

      def help_text(command = nil)
        key = command.to_s.strip.sub(/\A\//, "")
        return help_summary if key.empty?

        topic = HELP_TOPICS[key]
        return "help: unknown command /#{key} — say the work, or /help" unless topic

        (["/#{key} - #{topic[:summary]}"] + topic[:detail]).join("\n")
      end

      def slash_commands
        (HELP_TOPICS.keys.map { |k| "/#{k}" } + %w[/exit /quit /rollback]).uniq.sort
      end

      def help_summary
        lines = HELP_TOPICS.map { |cmd, topic| "/#{cmd} - #{topic[:summary]}" }
        lines << ""
        lines << "work is a sentence. /through is the one explicit pass."
        lines.join("\n")
      end
    end
  end
end
