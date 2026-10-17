# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # One topic per registered command, and the registry is the whole list.
      # test_command_registry_dispatch holds the two together, so a verb cannot
      # be built without a page or paged without being built.
      HELP_TOPICS = {
        "fix" => {
          summary: "the convergence loop: observe, critique, repair, observe again",
          detail: [
            "/fix [path] — the one operation that changes the tree. It reads the",
            "path, asks the council what is wrong, weighs competing repairs, applies",
            "the strongest, validates it and reads the path again, until the tree",
            "converges, stops improving or reaches something only you can settle.",
            "",
            "Detailed dmesg is the default: every meaningful event is shown as it happens.",
            "--trace expands the redacted event payload; --normal and --quiet reduce output;",
            "MASTER_CLI_QUIET=1 silences the unit lines in the interactive CLI.",
            "--dry-run stops after the reading and says what it would take on.",
            "There is no /scan: observation is where a fix starts, not a command.",
          ],
        },
        "deploy" => {
          summary: "deploy MASTER or the Rails fleet to vm23 through the canonical VPS path",
          detail: [
            "/deploy all --confirm — deploy MASTER, brgen, amber and bsdports to vm23.",
            "/deploy master --confirm — deploy MASTER to vm23.",
            "Deployment is always remote and review-gated. The command delegates to bin/operator",
            "and OPENBSD/bin/vps-deploy; it does not create a second deploy implementation.",
          ],
        },
        "review" => {
          summary: "read-only compatibility view over the /fix pipeline",
          detail: [
            "/review [path] — runs the /fix observation, critique and map stages",
            "without writing. /fix is the canonical lifecycle and owns repair.",
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
        "play" => {
summary: "render a Dilla progression with a drum pattern and play it on the local sound card",
detail: [
  "/play — a random progression and a random drum pattern, rendered to a wav and played.",
  "/play <progression> [drum pattern] — name either, or both; `ruby STUDIO/dilla/dilla.rb --list` prints the names.",
  "A render lands in the dilla-renders folder under your documents, dated, and is never written over.",
],
        },
        "plugin" => {
          summary: "list and invoke governed plugins",
          detail: [
            "/plugin — list installed plugins.",
            "/plugin info <id> — show one manifest.",
            "/plugin run <id> <action> <json> — invoke through the constitutional gate.",
            "social_browser covers OnlyFans and FetLife on supported desktop or Android/Termux runtimes.",
            "It permits explicit operator-owned or authorized actions and inbound replies only; no bulk outreach, friendship farming, deception or challenge bypass.",
            "air_superiority performs defensive Wi-Fi/Bluetooth observation and keeps only a local known-device baseline.",
          ],
        },
        "status" => {
          summary: "one-frame health, services and the known-good runtime",
          detail: ["/status — mode, git, fix loop, last pipeline stage, recent events.",
                   "/status mission — the current mission contract, stage, model, effort and goal.",
                   "/status services [name] — named cognitive subsystems and their state.",
                   "/status security — constitution, capability and self-change state.",
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
          summary: "show or switch the active model, inspect laboratory outcomes, and connect its subscriptions",
          detail: ["/model",
                   "/model <name> — choose a reachable lane from data/models.yml and the live pool.",
                   "/model list — list the reachable pool and the next steps to grow it.",
                   "/model health — calls, success rate, failures and measured response time from recorded outcomes.",
                   "Optional gateway: set MASTER_LLM_GATEWAY_URL to a local OpenAI-compatible /v1 URL; remote gateways require HTTPS.",
                   "Set MASTER_LLM_GATEWAY_KEY or FREELLMPOOL_PROXY_KEY when the gateway requires a bearer key.",
                   "/model benchmark — benchmark reachable Ollama models; /model benchmark all includes every reachable lane.",
                   "/model lab — summarize recorded trajectory quality by model.",
                   "/model auth — show subscription lanes and their authentication state.",
                   "/model auth login claude|chatgpt|grok — run the provider's official browser sign-in flow.",
                   "MASTER never receives or stores your password, OAuth code, cookies or session credentials."],
        },
        "android" => {
          summary: "start Android/Termux onboarding and pair the local owner",
          detail: ["/android [name] — begin personal onboarding on an Android/Termux host.",
                   "The command claims the local device owner on first use and starts the owner conversation."],
        },
        "ios" => {
          summary: "start iOS/PWA onboarding",
          detail: ["/ios — begin onboarding on an iPhone or iPad through the browser/PWA.",
                   "MASTER does not claim native iOS hardware access; browser capabilities remain explicit."],
        },
        "wake" => {
          summary: "control the Android/Termux wake-word listener",
          detail: ["/wake — report whether the local wake-word listener is enabled and which phrases it recognizes.",
                   "/wake on — enable the listener after explicit local owner access.",
                   "/wake off — disable the listener.",
                   "The listener is Android/Termux-only; web visitors cannot enable it."],
        },
        "doctor" => {
          summary: "host, provider, exposure and hardware health",
          detail: ["/doctor — keys, disk, git, pairing/gateway exposure.",
                   "/doctor device — truthful Android/Termux:API hardware capability report.",
                   "/doctor device battery|camera|sensors|audio — query the matching Termux:API endpoint.",
                   "/doctor device location [gps|network|passive] — explicitly request location; never sampled at boot."],
        },
        "voice" => {
          summary: "speech uses sensible defaults; optional voice styles are easy to discover",
          detail: ["/voice — current voice, mode, profile, speaking rate and recent latency.",
                   "/voice natural — restore clean, fast, everyday speech (the default).",
                   "/voice expressive — use the expressive synthesis pipeline.",
                   "/voice dilla — enable Dilla's effects rack and room.",
                   "/voice timing — show measured synthesis and first-audio timings; no launch flags needed.",
                   "/voice test — synthesize and play “MASTER voice test.” synchronously."],
        },
        "narrate" => {
          summary: "story narration of what MASTER is doing, on by default",
          detail: ["/narrate — state, beats told, model or template, cost against the cap.",
                   "/narrate on|off — tell the work as one running story, or fall back to plain one-line speech.",
                   "Pacing, caps and the model lane are in data/voice.yml under narration; MASTER_NARRATE=0 turns it off for a run."],
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
          summary: "write one source snapshot per governed tree at the pub4 root, sized for another model's context",
          detail: ["/snapshot — write snapshot_MASTER.md, snapshot_RAILS.md, snapshot_OPENBSD.md and snapshot_STUDIO.md at the pub4 root, deleting the old ones first.",
                   "Each is one file of about 95K tokens: a map of every file, then the most important source whole. For more of one area: bin/operator snapshot TREE --only=<dir>; for exact bytes: --mirror.",
                   "Snapshots are source packs, not runtime state; they are deliberately visible beside the trees they describe."],
        },
        "laws" => {
          summary: "the declared laws, one line each",
          detail: ["/laws [filter] — id, tier, severity and kind from data/laws.yml.",
                   "bin/operator laws <ID> prints one in full."],
        },
        "why" => {
          summary: "what a law says, and where it comes from",
          detail: ["/why <law|path|scan_rule|anti_pattern|style.key> — Trace::WhyExplainer looks it",
                   "up in the constitution, architecture and path ownership, then asks the model only when nothing matches."],
        },
        "wishlist" => {
          summary: "the governed assistant wishlist, with an honest state per workstream",
          detail: ["/wishlist — list the current convergence workstreams.",
                   "/wishlist <id|word> — inspect one workstream, its implementation anchor and proof owner.",
                   "The wishlist is non-authoritative. Constitution, code and evidence remain authoritative."],
        },
        "size" => {
          summary: "measured byte, file and Ruby-line mass for the four governed trees",
          detail: ["/size — measure MASTER, RAILS, OPENBSD and STUDIO.",
                   "/size MASTER|RAILS|OPENBSD|STUDIO — measure one tree.",
                   "The command reports observed mass; it never invents a health score."],
        },
        "explain" => {
          summary: "explain the living four-tree architecture from the checkout",
          detail: ["/explain — show the current PUB4 boundary and measured topology.",
                   "/explain MASTER|RAILS|OPENBSD|STUDIO — focus on one tree.",
                   "It reports what the checkout contains, not what an old README promised."],
        },
        "events" => {
          summary: "show the existing EventBus publisher/subscriber reach census",
          detail: ["/events — report published topics, consumers and browser listeners.",
                   "/events strict — use the same census as a blocking check for missing publishers or consumers."],
        },
        "prove" => {
          summary: "run the deterministic local PUB4 convergence proof and write a receipt",
          detail: ["/prove — check constitution presence, four-tree topology, command discoverability, wishlist anchors and snapshot contract.",
                   "/prove history [N] — show the most recent durable convergence receipts.",
                   "External hardware, vm23, staging money, browser and listening evidence remains INCONCLUSIVE until actually exercised."],
        },
        "face" => {
          summary: "the live terminal face with one clean stage and control strip",
          detail: [
            "/face — open the MASTER face in the alternate terminal screen, as large as the terminal allows.",
            "/face size auto|small|large|WxH — choose the face's size (WxH is columns by rows) and open it; the choice holds for the session.",
            "It uses the same TurnRouter, ear, mouth and runtime event bus as the shell.",
            "The face keeps a clean full-width stage; the latest exchange and controls stay in the bottom strip.",
            "Type a line, press enter, or speak while idle. Ctrl-C interrupts; Ctrl-D leaves.",
          ],
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

      # This taxonomy feeds both the terminal overview and the web palette.
      # Keep categories here rather than duplicating a second menu in JavaScript.
      COMMAND_CATEGORIES = {
        "fix" => "fix", "status" => "health", "doctor" => "health", "events" => "health",
        "session" => "session", "clear" => "session", "undo" => "session",
        "model" => "model", "plugin" => "model", "wake" => "model",
        "review" => "review", "critique" => "review", "laws" => "review",
        "why" => "review", "explain" => "review", "prove" => "review",
        "commit" => "change", "deploy" => "change", "snapshot" => "change",
        "orders" => "change", "wishlist" => "change",
        "face" => "interface", "voice" => "interface", "narrate" => "interface", "size" => "interface",
        "play" => "media", "android" => "media", "ios" => "media",
        "soul" => "constitution", "help" => "help", "exit" => "session", "quit" => "session",
      }.freeze

      CATEGORY_ORDER = %w[fix health session model review change interface media constitution help].freeze

      CATEGORY_LABELS = {
        "fix" => "fix", "health" => "health", "session" => "session",
        "model" => "model", "review" => "review", "change" => "change",
        "interface" => "interface", "media" => "media",
        "constitution" => "constitution", "help" => "help",
      }.freeze

      def command_surface
        slash_commands.filter_map do |slash|
          key = slash.delete_prefix("/")
          topic = HELP_TOPICS[key]
          next unless topic || %w[exit quit].include?(key)

          {
            cmd: slash,
            hint: topic ? topic[:summary] : "exit the session",
            category: COMMAND_CATEGORIES.fetch(key, "other"),
          }
        end
      end

      def help_summary
        CATEGORY_ORDER.map do |category|
          commands = COMMAND_CATEGORIES.filter_map do |name, assigned|
            "/#{name}" if assigned == category && name != "quit"
          end
          next if commands.empty?

          commands = commands.map { |command| command == "/fix" ? "/fix [path]" : command }
          commands.unshift("/help [command]") if category == "help"
          "#{category}0 at master0: #{commands.join(' ')}"
        end.compact.join("\n")
      end
    end
  end
end
