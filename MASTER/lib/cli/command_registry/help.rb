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
            "On a target inside one RAILS app, /fix then runs the layout loop on that app:",
            "bin/operator design, whose kept edits are local commits for you to review.",
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
summary: "play the curated Blue Hour Dilla showcase or a named progression through the canonical effects rig",
detail: [
  "/play — render and play the canonical Blue Hour Dilla showcase through the same arrangement and effects pipeline as ruby STUDIO/dilla/dilla.rb; video encoding is skipped.",
  "/play <progression> [drum pattern] — name either, or both; `ruby STUDIO/dilla/dilla.rb --list` prints the names.",
  "Bare /play renders the same arrangement as `ruby STUDIO/dilla/dilla.rb`; named progression requests use the Dilla pocket at 92 BPM unless an explicit or reference tempo applies.",
  "Each audition writes a distinct dated WAV and leaves reference dilla.wav and dilla_norsk.wav untouched.",
],
        },
        "support" => {
          summary: "practical personal support and a bounded synthetic quality benchmark",
          detail: [
            "/support — practical personal-advice guidance is routed automatically when relevant.",
            "/support benchmark --confirm [response-model] [judge-model] — evaluate up to eight synthetic cases, at most sixteen model calls.",
            "Use distinct accessible models for the response and judge when possible; otherwise independence is not proven.",
            "Review each answer, especially crisis and coercion cases. Scores are screening signals, not clinical certification.",
          ],
        },
        "screen" => {
          summary: "keep MASTER running in a screen session you can leave and reattach",
          detail: [
            "/screen [name] — start bin/master detached in a GNU screen session (default name master), or say it is already running.",
            "/screen list — the screen sessions on this machine. Reattach with `screen -r <name>`; detach with ctrl-a d.",
          ],
        },
        "plugin" => {
          summary: "list and invoke governed plugins",
          detail: [
            "/plugin — list installed plugins.",
            "/plugin info <id> — show one manifest.",
            "/plugin run <id> <action> <json> — invoke through the constitutional check.",
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
        "capabilities" => {
          summary: "discover core tools and optional plugin observation capabilities",
          detail: ["/capabilities — list registered tools and plugin observation actions.",
                   "/capabilities search <words> — search names and descriptions.",
                   "/capabilities describe <tool|plugin|plugin:id:action> — inspect metadata without running it.",
                   "The inventory is not a live health check. Plugins expose only declared read-only observations here; their own policy still governs execution."],
        },
        "skill" => {
          summary: "review declared skill contracts and approve or revoke one exact content revision",
          detail: [
            "/skill list — show declared contracts, risk, full content SHA-256, promotion readiness and approval state.",
            "/skill inspect NAME — inspect metadata, required capabilities, Law IDs and fixture references without printing the skill body.",
            "/skill approve NAME SHA256 --confirm — approve only the exact currently loaded candidate revision, as the local operator.",
            "/skill revoke NAME SHA256 --confirm — revoke one exact revision, including an older revision after the skill has changed.",
            "Declared skills are not injected until an operator-owned ~/.master/skill_approvals.yml entry matches their exact revision. Approval reads each declared fixture inside the skill directory and records its digest; it never executes one.",
          ],
        },
        "task" => {
          summary: "keep a durable private task list with bounded steps and evidence",
          detail: ["/task — list open work and flag overdue due dates; no background notifications are sent.",
                   "/task create <title> | show <id> | search <words>.",
                   "/task step <id> <title> — add a step. /task start-step <id> <step-id> <note> marks work started.",
                   "/task verify-step <id> <step-id> <evidence> records evidence; it is not independently authenticated.",
                   "/task block-step <id> <step-id> <reason> | block <id> <reason> | resume <id> <note>.",
                   "/task complete <id> <evidence> requires every step to be verified. /task update <id> title|description|priority|due_at <value>.",
                   "Tasks stay in an owner-local, permission-restricted file. MASTER does not execute task steps. A task with a due time rings in an open interactive session, and only there."],
        },
        "agenda" => {
          summary: "read a paired owner's imported local calendar",
          detail: [
            "/agenda status — report whether an iCalendar export has been imported.",
            "/agenda import /path/to/calendar.ics — import a local .ics file into the private paired workspace; quote paths containing spaces.",
            "/agenda today or /agenda YYYY-MM-DD — list events for a date without changing the source calendar.",
            "First run /privacy grant calendar_read in the paired local session. Import is local-only and read-only; remote calendar accounts are not connected. Events with RRULE or RDATE are flagged but recurrence is not expanded, so verify those series in the source calendar.",
          ],
        },
        "pair" => {
          summary: "issue and redeem one-time pairing codes for consent-gated local access",
          detail: [
            "/pair or /pair status — show pairing and local-device status.",
            "/pair issue [label] — issue a one-time code and show its expiry.",
            "/pair <code> — redeem a code. Pairing grants messaging tools, not operator shell access.",
            "/pair list — list paired subjects; /pair revoke <token> revokes a pairing.",
            "Keep the code private and redeem it only on the intended local device.",
          ],
        },
        "preferences" => {
          summary: "inspect and control per-person interaction settings and staged suggestions",
          detail: [
            "/preferences or /preferences show — list active settings, scopes, provenance and pending suggestions.",
            "/preferences set KEY=VALUE [scope=SCOPE] — set a validated preference; keys and values appear below.",
            "Keys: communication.tone=direct|warm|neutral; communication.detail=brief|balanced|detailed;",
            "reasoning.approach=pragmatic|first_principles|compare_options; work.flow=recommend|plan_first|implement_verify;",
            "research.depth=quick|standard|deep; learning.format=step_by_step|worked_examples|socratic.",
            "Scopes: all, coding, research, support, creative, planning. A scoped value overrides the all-scope value.",
            "/preferences learn on|off — observe a narrow set of repeated, low-risk correction phrases; the same signal must recur in two user turns before staging an inactive suggestion.",
            "Turning learning off clears unconfirmed automatic observations and suggestions; owner-created suggestions remain available.",
            "Raw user messages are not stored as learning evidence. Suggestions remain inactive until the owner explicitly accepts an ID.",
            "/preferences suggest KEY=VALUE [scope=SCOPE] [reason=\"...\"] — stage an inactive candidate; /preferences accept ID or /preferences reject ID decides it.",
            "/preferences forget KEY [scope=SCOPE] | /preferences reset --confirm | /preferences export.",
            "Requires a paired local subject and the existing /privacy grant personal_memory permission. Preferences never grant tool authority or override Laws.",
          ],
        },
        "privacy" => {
          summary: "inspect personal-memory consent and manage the paired subject's stored data",
          detail: [
            "/privacy — show whether personal profile and memory are enabled for the paired subject.",
            "/privacy grant personal_memory — explicitly allow this local paired subject's profile and memory to be read and written.",
            "/privacy revoke personal_memory — immediately disable that scope for this subject.",
            "/privacy grant calendar_read or /privacy revoke calendar_read — enable or immediately disable access to the paired subject's imported local calendar.",
            "/privacy memory show or /privacy memory export — inspect the paired subject's complete USER.md profile and MEMORY.md, within a bounded export size.",
            "/privacy memory forget --confirm — clear durable memory while preserving USER.md. The exact confirmation command is required.",
            "The command is local-only. Microphone, camera, location, messages, purchases, deployment and financial scopes cannot be granted here until their execution adapters enforce the same policy and native OS permissions.",
          ],
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
                   "/doctor device location [gps|network|passive] — explicitly request location; never sampled at boot.",
                   "/doctor tools [reconcile <id> <outcome> <evidence>] — tool calls with an unknown outcome, and their release."],
        },
        "voice" => {
          summary: "CLI speech is off by default; enable it explicitly when wanted",
          detail: ["/voice — current voice, mode, profile, speaking rate and recent latency.",
                   "/voice on|off — enable or silence CLI speech for this session; default is off.",
                   "/voice natural — select clean, fast, everyday speech.",
                   "/voice expressive — use the expressive synthesis pipeline.",
                   "/voice dilla — enable Dilla's effects rack and room.",
                   "/voice timing — show measured synthesis and first-audio timings; no launch flags needed.",
                   "/voice test — synthesize and play “MASTER voice test.” synchronously.",
                   "The web face keeps its own TTS path enabled; CLI speech does not control browser audio."],
        },
        "narrate" => {
          summary: "story narration of what MASTER is doing, on by default",
          detail: ["/narrate — state, beats told, model or template, cost against the cap.",
                   "/narrate on|off — tell the work as one running story, or fall back to plain one-line speech.",
                   "Pacing, caps and the model lane are in data/voice.yml under narration; MASTER_NARRATE=0 turns it off for a run."],
        },
        "incident" => {
          summary: "a private dated log of what happened, kept on this machine",
          detail: ["/incident add <what happened> — keep a dated note; nothing is recorded or sent.",
                   "/incident list — the notes in order. /incident summary — counts by week, weekday and part of day.",
                   "The counts describe your notes; they cannot show what was said."],
        },
        "reload" => {
          detail: ["/reload — restart this session in place so edits to lib/ and data/ take effect.",
                   "The conversation is kept; the beat and speech stop first."],
        },
        "bard" => {
          summary: "lyrical telling of what MASTER is doing, on by default",
          detail: ["/bard — state, beats told, model or template, cost against the cap.",
                   "/bard on|off — sing the work as one continuous song, or hand it back to the plain /narrate voice.",
                   "One teller speaks at a time. data/bard.yml lays the lyrical script over data/narration.yml; " \
                   "MASTER_BARD=0 turns it off for a run."],
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
            "Bare bin/master opens the original Ruby REPL prompt; /face opens its full-screen visual stage.",
            "The face renders the same live prompt and session rather than creating a host:path shell prompt.",
            "Ctrl-C interrupts active listening, thinking or speech, or clears a draft; it never exits the face. Ctrl-D returns to the REPL.",
            "The web chat and terminal share the location-aware Operator prompt, TurnRouter and command registry.",
            "MASTER_FACE_ON_START=1 opens the face at start. /fix and other long commands run on the shell surface.",
            "While idle it listens through the microphone and says so on its status line (mic on).",
            "Type to take the floor.",
            "It uses the same TurnRouter, ear, mouth and runtime event bus as the shell.",
            "The face keeps a clean full-width stage; the latest exchange and controls stay in the bottom strip.",
            "Type a line, press Enter, or speak while idle. Speech failures keep the answer visible as text.",
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
        "session" => "session", "pair" => "session", "clear" => "session", "undo" => "session",
        "model" => "model", "plugin" => "model", "screen" => "session", "wake" => "model",
        "privacy" => "constitution", "preferences" => "interface", "agenda" => "session", "task" => "session", "skill" => "constitution", "capabilities" => "model",
        "review" => "review", "critique" => "review", "laws" => "review",
        "why" => "review", "explain" => "review", "prove" => "review",
        "commit" => "change", "deploy" => "change", "snapshot" => "change",
        "orders" => "change", "wishlist" => "change",
        "face" => "interface", "voice" => "interface", "narrate" => "interface", "bard" => "interface",
        "reload" => "session", "incident" => "session",
        "size" => "interface",
        "play" => "media", "android" => "media", "ios" => "media",
        "support" => "review",
        "soul" => "constitution", "help" => "help", "exit" => "session", "quit" => "session",
      }.freeze

      CATEGORY_ORDER = %w[fix health session model review change interface media constitution help].freeze

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
        lines = CATEGORY_ORDER.filter_map do |category|
          commands = COMMAND_CATEGORIES.filter_map do |name, assigned|
            "/#{name}" if assigned == category
          end
          next if commands.empty?

          commands = commands.map { |command| command == "/fix" ? "/fix [path]" : command }
          commands = commands.reject { |command| command == "/help" } if category == "help"
          commands.unshift("/help [command]") if category == "help"
          "#{category}0 at master0: #{commands.join(' ')}"
        end
        lines << "input0 at master0: describe work in plain language; slash commands are optional."
        lines << "fix0 at master0: /fix [path] writes; /review and /critique read; /help <command> shows syntax."
        lines.join("\n")
      end
    end
  end
end
