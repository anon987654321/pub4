# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # One topic per registered command, and the registry is the whole list.
      # test_command_registry_dispatch holds the two together, so a verb cannot
      # be built without a page or paged without being built.
      HELP_TOPICS = {
        "face" => {
          summary: "the Braille face, listening, in this terminal",
          detail: [
            "/face — the same head the web face draws, as Braille in a phone-sized",
            "window. It listens while idle, speaks the reply, and the session keeps",
            "what was said. Type a line to send it as text. ^D leaves.",
          ],
        },
        "fix" => {
          summary: "the convergence loop: observe, critique, repair, observe again",
          detail: [
            "/fix [path] — the one operation that changes the tree. It reads the",
            "path, asks the council what is wrong, weighs competing repairs, applies",
            "the strongest, validates it and reads the path again, until the tree",
            "converges, stops improving or reaches something only you can settle.",
            "",
            "Detailed dmesg is the default: every meaningful event is shown as it happens.",
            "--trace expands the redacted event payload; --normal and --quiet reduce output.",
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
        "critique" => {
          summary: "read-only: the council, without the principle map",
          detail: [
            "/critique [path] — run the council against the path. It reads and argues, then stops.",
            "/review runs the critique plus the principle map; /fix is the operation that writes.",
          ],
        },
        "plugin" => {
          summary: "list and invoke governed plugins",
          detail: [
            "/plugin — list installed plugins.",
            "/plugin info <id> — show one manifest.",
            "/plugin run <id> <action> <json> — invoke through the constitutional gate.",
            "social_browser covers OnlyFans, FetLife and Snapchat on supported desktop or Android/Termux runtimes.",
            "It permits explicit operator-owned or authorized actions and inbound replies only; no bulk outreach, friendship farming, deception or challenge bypass.",
            "air_superiority performs defensive Wi-Fi/Bluetooth observation and keeps only a local known-device baseline.",
          ],
        },
        "status" => {
          summary: "one-frame health, the mission and the known-good runtime",
          detail: ["/status — mode, git, fix loop, last pipeline stage, recent events.",
                   "/status mission — the current mission contract, stage, model, effort and goal.",
                   "The mission persists across interruption; artifacts and checkpoints remain separate evidence.",
                   "/status runtime — the recorded known-good commit.",
                   "/status runtime promote — record the current committed HEAD as known-good.",
                   "/status runtime rollback --confirm — return a clean checkout to the recorded known-good commit."],
        },
        "undo" => {
          summary: "revert the last recorded change",
          detail: ["/undo — the last change this session recorded."],
        },
        "commit" => {
          summary: "commit the named paths",
          detail: [
            "/commit <path>... --confirm — stage and commit the named paths and nothing else,",
            "with a model-written message. Paths are relative to MASTER/.",
          ],
        },
        "model" => {
          summary: "show or switch the active model, and connect its subscriptions",
          detail: ["/model", "/model <name> — routing from data/models.yml.", "/model benchmark — benchmark reachable Ollama models; /model benchmark all includes every reachable lane.",
                   "/model auth — show subscription lanes and their authentication state.",
                   "/model auth login claude|chatgpt|grok — run the provider's official browser sign-in flow.",
                   "MASTER never receives or stores your password, OAuth code, cookies or session credentials."],
        },
        "pair" => {
          summary: "issue or redeem a pairing code",
          detail: ["/pair owner [label]", "/pair issue [label]", "/pair <code>", "/pair status"],
        },
        "device" => {
          summary: "show local phone agent and owner state",
          detail: ["/device"],
        },
        "doctor" => {
          summary: "host, provider, exposure and hardware health",
          detail: ["/doctor — keys, disk, git, pairing/gateway exposure.",
                   "/doctor device — truthful Android/Termux:API hardware capability report.",
                   "/doctor device battery|camera|sensors|audio — query the matching Termux:API endpoint.",
                   "/doctor device location [gps|network|passive] — explicitly request location; never sampled at boot."],
        },
        "help" => {
          summary: "this list",
          detail: ["/help", "/help <command>"],
        },
        "clear" => {
          summary: "clear the session transcript",
          detail: ["/clear — does not undo file changes."],
        },
        "session" => {
          summary: "the conversations: list, continue or branch one",
          detail: ["/session — list sessions; the current one is marked with *.",
                   "/session continue <id> — switch the active conversation; resume is the same word.",
                   "/session fork [id] — clone the current conversation and continue in the new branch."],
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
                   "/soul rollback undoes the last amendment. Absolute sections do not move.",
                   "/soul law or /soul law contract — generated contract for MASTER and external LLMs.",
                   "/soul law full — complete law questions, fixes and proof examples.",
                   "/soul law digest — current executable-law identity.",
                   "/soul law handshake — export the exact contract an external agent must present before admission.",
                   "/soul law protocol — the mandatory enforcement sequence."],
        },
        "snapshot" => {
          summary: "write the current MASTER tree and source to one Markdown artifact",
          detail: ["/snapshot — write pub4/snapshot_MASTER.md.",
                   "/snapshot <output> — write the snapshot to a chosen path inside pub4."],
        },
        "rules" => {
          summary: "the declared rules, one line each",
          detail: ["/rules [filter] — id, tier, severity and kind from data/rules.yml.",
                   "bin/operator rules <ID> prints one in full."],
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
        (HELP_TOPICS.keys.map { |k| "/#{k}" } + %w[/exit /quit]).uniq.sort
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
