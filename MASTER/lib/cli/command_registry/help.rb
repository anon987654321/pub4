# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # One topic per registered command, and the registry is the whole list:
      # `build` returns clear, commit, doctor, help, model, orders, pair,
      # rollback, soul, status, through, undo and why, and nothing else reaches
      # Stages::Route. The other command tables in this directory — memory,
      # system, media, core, domain, reach, agent — are built by no caller, so
      # /dilla, /btw, /tree and the rest have a dispatcher and no route. Writing
      # them a help topic would advertise a command the router cannot resolve,
      # which is why test_cli_domain_commands pins that /domain stays unlisted.
      HELP_TOPICS = {
        "through" => {
          summary: "the one verb: scan (which fixes), critique, principle map",
          detail: [
            "/through [path] — every stage: aesthetic scan, deep scan, fix, re-scan,",
            "critique, principle map. Or just say the path.",
            "",
            "--only <stage> runs one part. The stages are scan, critique and map;",
            "`fix` is a spelling of scan and `council` of critique, because the scan",
            "stage fixes what it finds on the spot rather than leaving it to be",
            "relocated later.",
            "",
            "/scan, /fix, /critique and /council are those stages by name —",
            "/scan is /through --only scan. There is one verb underneath.",
            "",
            "Mechanical autofix writes on each file as it is scanned;",
            "--dry-run / --no-autofix preview without writing.",
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
        "orders" => {
          summary: "standing orders — the work that runs without being asked",
          detail: ["/orders", "/orders enable|disable|reset <name>", "/orders run",
                   "/orders add name=<name> cmd=<command> — the table is data/state.yml."],
        },
        "soul" => {
          summary: "read and amend the constitution",
          detail: ["/soul — the summary. /soul version, /soul diff.",
                   "/soul propose <rationale> then /soul approve or /soul reject;",
                   "/soul rollback undoes the last amendment. Absolute sections do not move."],
        },
        "why" => {
          summary: "what a rule says, and where it comes from",
          detail: ["/why <law|scan_rule|anti_pattern|style.key> — Trace::WhyExplainer looks it",
                   "up in law/ and data/rules.yml, and asks the model only when nothing matches."],
        },
      }.freeze

      # /rollback is /undo registered twice, so help answers for it under the
      # name the user typed. It gets no topic of its own — two entries print the
      # same sentence twice in the summary, and the surface is one command.
      ALIASES = { "rollback" => "undo" }.freeze

      def help_text(command = nil)
        key = command.to_s.strip.sub(/\A\//, "")
        return help_summary if key.empty?

        name = ALIASES.fetch(key, key)
        topic = HELP_TOPICS[name]
        return unknown_command_text(key) unless topic

        (["/#{key} - #{topic[:summary]}"] + topic[:detail]).join("\n")
      end

      # The surface is closed, so a name with no topic is not a documented
      # command missing its page — it is not a command. Say which is which,
      # rather than leaving a reader to look for a page nobody wrote.
      def unknown_command_text(key)
        "help: unknown command /#{key} — the slash surface is #{slash_commands.size} commands " \
          "and closed. /help lists them; everything else is said in a sentence."
      end

      def slash_commands
        (HELP_TOPICS.keys.map { |k| "/#{k}" } + ALIASES.keys.map { |k| "/#{k}" } + %w[/exit /quit]).uniq.sort
      end

      def help_summary
        lines = HELP_TOPICS.map { |cmd, topic| "/#{cmd} - #{topic[:summary]}" }
        lines << ""
        lines << "work is a sentence. /through is the one explicit pass, and"
        lines << "/scan /fix /critique /council are its stages: /through --only <stage>."
        lines.join("\n")
      end
    end
  end
end
