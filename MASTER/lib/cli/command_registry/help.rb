# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # One topic per registered command, and the registry is the whole list:
      # `build` returns clear, commit, doctor, fix, help, model, orders, pair,
      # review, rollback, rules, soul, status, undo and why, and nothing reaches
      # Stages::Route. test_command_registry_dispatch holds the two together, so a
      # verb cannot be built without a page or paged without being built.
      HELP_TOPICS = {
        "fix" => {
          summary: "the convergence loop: observe, critique, repair, observe again",
          detail: [
            "/fix [path] — the one operation that changes the tree. It reads the",
            "path, asks the council what is wrong, weighs competing repairs, applies",
            "the strongest, validates it and reads the path again, until the tree",
            "converges, stops improving or reaches something only you can settle.",
            "",
            "--dry-run stops after the reading and says what it would take on.",
            "There is no /scan: observation is where a fix starts, not a command.",
          ],
        },
        "review" => {
          summary: "read-only: the council and the principle map",
          detail: [
            "/review [path] — the council reads the path and argues about it, then",
            "the principle map. It writes nothing; /fix is the verb that writes.",
            "",
            "--only <stage> runs one part: --only critique or --only map, and",
            "`council` is a spelling of critique. --only fix gives the reading and",
            "what a repair would take on, without taking it on.",
          ],
        },
        "plugin" => {
          summary: "list and invoke installed MASTER plugins",
          detail: [
            "/plugin — list built-in plugins.",
            "/plugin info <id> — show a plugin manifest.",
            "/plugin run <id> <action> <json> — invoke a plugin action through the constitutional policy gate.",
            "The social browser is limited to operator-owned or authorized accounts, explicit outbound consent and inbound replies; it does not bulk-message, farm friendships, bypass challenges or hide identity.",
            "Air Superiority performs defensive Wi-Fi/Bluetooth observation and maintains only a local known-device baseline.",
          ],
        },
        "device" => {
          summary: "Android and Termux:API hardware capabilities",
          detail: ["/device — truthful hardware/API capability report.",
                   "/device battery|camera|sensors|audio — query the matching Termux:API endpoint.",
                   "/device location [gps|network|passive] — explicitly request location; never sampled at boot."],
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
          summary: "commit the named paths",
          detail: [
            "/commit <path>... --confirm — stage and commit the named paths and nothing else,",
            "with a model-written message. Paths are relative to MASTER/.",
          ],
        },
        "model" => {
          summary: "show or switch the active model",
          detail: ["/model", "/model <name> — routing from data/models.yml.", "/model benchmark — benchmark reachable Ollama models; /model benchmark all includes every reachable lane."],
        },
        "auth" => {
          summary: "connect subscription compute through the provider's official CLI",
          detail: ["/auth — show subscription lanes.", "/auth status — show installed and known authentication state.",
                   "/auth login claude|chatgpt|grok — run the provider's official browser sign-in flow.",
                   "MASTER never receives or stores your password, OAuth code, cookies or session credentials."],
        },
        "pair" => {
          summary: "issue or redeem a pairing code",
          detail: ["/pair issue [label]", "/pair <code>", "/pair status"],
        },
        "doctor" => {
          summary: "host, provider, and exposure health",
          detail: ["/doctor — keys, disk, git, pairing/gateway exposure."],
        },
        "runtime" => {
          summary: "known-good runtime promotion and rollback",
          detail: ["/runtime status", "/runtime promote — record the current committed HEAD as known-good.",
                   "/runtime rollback --confirm — return a clean checkout to the recorded known-good commit."],
        },
        "help" => {
          summary: "this list",
          detail: ["/help", "/help <command>"],
        },
        "clear" => {
          summary: "clear the session transcript",
          detail: ["/clear — does not undo file changes."],
        },
        "sessions" => {
          summary: "list the in-memory conversation sessions",
          detail: ["/sessions — list sessions; the current one is marked with *.",
                   "/continue <id> or /resume <id> — switch to an existing session."],
        },
        "continue" => {
          summary: "continue an existing conversation",
          detail: ["/continue <id> — switch the active conversation.", "/resume <id> is an alias."],
        },
        "fork" => {
          summary: "branch the current conversation",
          detail: ["/fork [id] — clone the current conversation and continue in the new branch."],
        },
        "orders" => {
          summary: "the objective ledger — the work that runs without being asked",
          detail: ["/orders", "/orders enable|disable|reset <name>", "/orders run",
                   "/orders consent|revoke <domain> — finance, household and devices start off",
                   "/orders add name=<n> [domain=] [wake=] [every=] [verify=] [cmd=] — declared orders are data/state.yml."],
        },
        "soul" => {
          summary: "read and amend the constitution",
          detail: ["/soul — the summary. /soul version, /soul diff.",
                   "/soul propose <rationale> then /soul approve or /soul reject;",
                   "/soul rollback undoes the last amendment. Absolute sections do not move."],
        },
        "law" => {
          summary: "the portable enforcement contract",
          detail: ["/law or /law contract — generated contract for MASTER and external LLMs.",
                   "/law full — complete law questions, fixes and proof examples.",
                   "/law digest — current executable-law identity.",
                   "/law handshake — export the exact contract an external agent must present before admission.",
                   "/law protocol — the mandatory enforcement sequence."],
        },
        "snapshot" => {
          summary: "write the current MASTER tree and source to one Markdown artifact",
          detail: ["/snapshot — write pub4/snapshot_MASTER.md.",
                   "/snapshot <output> — write the snapshot to a chosen path inside pub4."],
        },
        "rules" => {
          summary: "the declared rules, one line each",
          detail: ["/rules [filter] — id, tier, severity and kind from data/rules.yml.",
                   "bin/operator rule <ID> prints one in full."],
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
      ALIASES = { "rollback" => "undo", "resume" => "continue" }.freeze

      def help_text(command = nil)
        key = command.to_s.strip.sub(/\A\//, "")
        return help_summary if key.empty?

        name = ALIASES.fetch(key, key)
        topic = HELP_TOPICS[name]
        return unknown_command_text(key) unless topic

        (["/#{key} — #{topic[:summary]}"] + topic[:detail]).join("\n")
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

      # The list is a table, so its second column is aligned; everywhere else
      # in the CLI one space separates.
      def help_summary
        width = HELP_TOPICS.keys.map(&:length).max + 1
        lines = HELP_TOPICS.map { |cmd, topic| "/#{cmd.ljust(width)} #{topic[:summary]}" }
        lines << ""
        lines << "work is a sentence. /fix is the one operation that writes: it observes,"
        lines << "critiques, repairs and observes again until the tree converges."
        lines << "/review and /critique read and argue without changing anything."
        lines.join("\n")
      end
    end
  end
end
