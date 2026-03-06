# frozen_string_literal: true

module MASTER
  # CommandRegistry - single source of truth for all commands, aliases, and handlers.
  # Aliases are embedded in each command's :aliases array. No separate legacy table.
  module CommandRegistry
    module_function

    COMMANDS = {
      # ── Queries ────────────────────────────────────────────────────────────
      ask: {
        desc: "Ask the LLM a question", usage: "ask <question>", group: :query,
        handler: ->(args, pipeline:) { MASTER::Commands.ask_question(args); HANDLED }
      },
      refactor: {
        desc: "Refactor file or directory (--recursive for dir)",
        usage: "refactor <path> [--recursive]", group: :analysis,
        aliases: %w[autofix multi-refactor mrefactor],
        handler: ->(args, pipeline:) {
          if args.to_s.include?("--recursive")
            MASTER::Commands.multi_refactor(args)
          else
            MASTER::Commands.autofix(args)
          end
          HANDLED
        }
      },
      chamber:  { desc: "Multi-model deliberation",          usage: "chamber <file>",    group: :query,
                  handler: ->(args, pipeline:) { MASTER::Commands.chamber_review(args); HANDLED } },
      evolve:   { desc: "Self-improvement cycle",            usage: "evolve [path]",     group: :query,
                  handler: ->(args, pipeline:) { MASTER::Commands.evolve_codebase(args); HANDLED } },
      ideate:   { desc: "Generate alternatives for a topic", usage: "ideate <topic>",    group: :query,
                  aliases: %w[brainstorm],
                  handler: ->(args, pipeline:) { MASTER::Commands.ideate(args); HANDLED } },
      creative: { desc: "Creative chamber",                  usage: "creative <prompt>", group: :query,
                  handler: ->(args, pipeline:) { MASTER::Commands.creative_chamber(args); HANDLED } },
      chat:     { desc: "Focused chat mode",                 usage: "chat [topic]",      group: :query,
                  handler: ->(args, pipeline:) { MASTER::Commands.chat_mode(args); HANDLED } },

      # ── Analysis ───────────────────────────────────────────────────────────
      # scan now handles hunt, critique, conflict, opportunities, learn, converge, self
      scan: {
        desc: "Code analysis (smells, bugs, critique, opportunities, self-run)",
        usage: "scan [path] [--hunt|--critique|--opportunities|--learn|--self|--converge]",
        group: :analysis,
        aliases: %w[hunt critique conflict opportunities opps learn converge
                    self selftest self-test selfrun self-run],
        handler: ->(args, pipeline:) { MASTER::Commands.scan_code(args); HANDLED }
      },
      fix: {
        desc: "Fix violations in file or directory", usage: "fix [--all|path]",
        group: :analysis,
        handler: ->(args, pipeline:) { MASTER::Commands.fix_code(args); HANDLED }
      },

      # ── Session ────────────────────────────────────────────────────────────
      session: {
        desc: "Session management",
        usage: "session <info|list|save|load|undo|summary|capture|review-captures|recent> [args]",
        group: :session,
        aliases: %w[sessions forget undo summary capture session-capture review-captures recent],
        handler: ->(args, pipeline:) { MASTER::Commands.manage_session(args); HANDLED }
      },

      # ── System ─────────────────────────────────────────────────────────────
      # status: dashboard + sub-flags for budget / context / history
      status: {
        desc: "System status (dashboard, budget, context, history)",
        usage: "status [--budget|--context|--history]", group: :system,
        aliases: %w[budget context history],
        handler: ->(args, pipeline:) {
          case args.to_s.strip
          when "--budget"  then MASTER::Commands.print_budget
          when "--context" then MASTER::Commands.print_context_usage
          when "--history" then MASTER::Commands.print_cost_history
          else MASTER::Dashboard.new.render
          end
          HANDLED
        }
      },

      # health: covers doctor and bootstrap
      health: {
        desc: "Health check, diagnostics, and setup",
        usage: "health [--deep|--setup]", group: :system,
        aliases: %w[doctor bootstrap],
        handler: ->(args, pipeline:) { MASTER::Commands.print_health(args); HANDLED }
      },

      # introspect: friction, architect, deps, config-drift
      introspect: {
        desc: "Internal introspection (friction, architect, deps, config-drift)",
        usage: "introspect [friction|architect|deps|config-drift]", group: :system,
        aliases: %w[retrospect friction architect arch architecture deps who-requires config-drift],
        handler: ->(args, pipeline:) {
          case args.to_s.strip
          when "architect", "arch", "architecture" then MASTER::Commands.print_architect
          when "deps", "who-requires"              then MASTER::Commands.print_deps(args)
          when "config-drift"                      then MASTER::Commands.print_config_drift
          else                                          MASTER::Commands.print_introspection(args)
          end
          HANDLED
        }
      },

      # system: schedule, heartbeat, policy, cache, init
      system: {
        desc: "System management (schedule, heartbeat, policy, cache, init)",
        usage: "system <subcommand> [args]", group: :system,
        aliases: %w[schedule heartbeat policy cache init-instructions],
        handler: ->(args, pipeline:) {
          sub, rest = args.to_s.split(/\s+/, 2)
          case sub
          when "schedule"                  then MASTER::Commands.manage_schedule(rest)
          when "heartbeat"                 then MASTER::Commands.manage_heartbeat(rest)
          when "policy"                    then MASTER::Commands.manage_policy(rest)
          when "cache"                     then MASTER::Commands.show_cache_stats(rest)
          when "init", "init-instructions" then MASTER::Commands.init_instructions(force: rest.to_s.include?("--force"))
          else puts "Unknown system subcommand. Try: schedule, heartbeat, policy, cache, init"
          end
          HANDLED
        }
      },

      # project: goal, remember, snapshot
      project: {
        desc: "Project context (goal, remember, snapshot)",
        usage: "project <subcommand> [args]", group: :system,
        aliases: %w[goal remember forget-goal snapshot showp],
        handler: ->(args, pipeline:) {
          sub, rest = args.to_s.split(/\s+/, 2)
          case sub
          when "goal"              then MASTER::Commands.project_goal(rest)
          when "remember"          then MASTER::Commands.project_remember(rest)
          when "forget", "forget-goal" then MASTER::Commands.project_forget
          when "snapshot", "showp" then MASTER::Commands.run_snapshot(rest)
          else puts "Unknown project subcommand. Try: goal, remember, forget, snapshot"
          end
          HANDLED
        }
      },

      # config: model, pattern, persona
      config: {
        desc: "Configuration (model, pattern, persona)",
        usage: "config <model|pattern|persona> [args]", group: :system,
        aliases: %w[model use models pattern mode patterns modes persona personas],
        handler: ->(args, pipeline:) {
          sub, rest = args.to_s.split(/\s+/, 2)
          case sub
          when "model", "models"
            rest.to_s.empty? || rest == "list" ? MASTER::Commands.list_models : MASTER::Commands.select_model(rest)
          when "pattern", "patterns", "mode", "modes"
            rest.to_s.empty? || rest == "list" ? MASTER::Commands.list_patterns : MASTER::Commands.select_pattern(rest)
          when "persona", "personas"
            rest.to_s.empty? || rest == "list" ? MASTER::Commands.list_personas : MASTER::Commands.manage_persona(rest)
          else puts "Unknown config subcommand. Try: model, pattern, persona"
          end
          HANDLED
        }
      },

      # Remaining system standalones
      codify:          { desc: "Show/export codified design rules",        usage: "codify [export-json]",  group: :system,
                         handler: ->(args, pipeline:) { MASTER::Commands.show_codified_rules(args); HANDLED } },
      "style-guides":  { desc: "List/sync style guides",                   usage: "style-guides [sync]",   group: :system,
                         aliases: %w[styleguides],
                         handler: ->(args, pipeline:) { MASTER::Commands.manage_style_guides(args); HANDLED } },
      axioms:          { desc: "Axioms and violation statistics",          usage: "axioms [--stats]",      group: :system,
                         aliases: %w[axioms-stats stats language-axioms],
                         handler: ->(args, pipeline:) {
                           if args.to_s.include?("--stats")
                             MASTER::Commands.print_axiom_stats
                           else
                             MASTER::Commands.print_language_axioms(args)
                           end
                           HANDLED
                         } },
      "history-dig":   { desc: "Recover deleted historical file",         usage: "history-dig [file]",    group: :system,
                         handler: ->(args, pipeline:) { MASTER::Commands.history_dig(args); HANDLED } },
      workflow:        { desc: "Workflow control",                          usage: "workflow <cmd>",        group: :system,
                         handler: ->(args, pipeline:) { MASTER::Commands.manage_workflow(args); HANDLED } },

      # ── Utilities ──────────────────────────────────────────────────────────
      # web: server + webtest
      web: {
        desc: "Web server control", usage: "web <start|test> [args]", group: :util,
        aliases: %w[server webtest web-test],
        handler: ->(args, pipeline:) {
          sub, rest = args.to_s.split(/\s+/, 2)
          case sub
          when "start"        then MASTER::Commands.start_web_server(rest)
          when "test", nil, "" then MASTER::Commands.run_webtest(rest)
          else puts "Unknown web subcommand. Try: start, test"
          end
          HANDLED
        }
      },

      # media: replicate image/video, narration, postpro
      media: {
        desc: "Media generation (image, video, narration, upscale)",
        usage: "media <generate|upscale|narrate> [args]", group: :util,
        aliases: %w[replicate repligen generate-image generate-video narrate narration postpro enhance upscale],
        handler: ->(args, pipeline:) {
          sub, rest = args.to_s.split(/\s+/, 2)
          case sub
          when "generate", "generate-image", "generate-video" then MASTER::Commands.replicate_command("replicate", rest)
          when "upscale", "enhance", "postpro"                then MASTER::Commands.postpro_command("postpro", rest)
          when "narrate", "narration"                         then MASTER::Commands.narrate_command(rest)
          else puts "Unknown media subcommand. Try: generate, upscale, narrate"
          end
          HANDLED
        }
      },

      speak:   { desc: "Text-to-speech",       usage: "speak <text>",  group: :util, aliases: %w[say],
                 handler: ->(args, pipeline:) { MASTER::Commands.speak(args); HANDLED } },
      browse:  { desc: "Browse and extract URL", usage: "browse <url>", group: :util,
                 handler: ->(args, pipeline:) { MASTER::Commands.browse_url(args); HANDLED } },
      queue:   { desc: "Queue operations",      usage: "queue <cmd>",   group: :util,
                 handler: ->(args, pipeline:) { MASTER::Commands.manage_queue(args); HANDLED } },
      harvest: { desc: "Data harvesting",       usage: "harvest <target>", group: :util,
                 handler: ->(args, pipeline:) { MASTER::Commands.harvest_data(args); HANDLED } },
      shell:   { desc: "Interactive shell",     usage: "shell",         group: :util,
                 handler: ->(args, pipeline:) { MASTER::Commands.open_shell; HANDLED } },
      clear:   { desc: "Clear screen",          usage: "clear",         group: :util,
                 handler: ->(args, pipeline:) { print "\e[2J\e[H"; HANDLED } },
      help:    { desc: "Show help",             usage: "help [command]", group: :util, aliases: %w[?],
                 handler: ->(args, pipeline:) { MASTER::Commands.show_help(args); HANDLED } },
      version: { desc: "Show version",          usage: "version",       group: :util, aliases: %w[ver --version -v],
                 handler: ->(args, pipeline:) { MASTER::Commands.show_version; HANDLED } },
      exit:    { desc: "Exit MASTER",           usage: "exit",          group: :util, aliases: %w[quit],
                 handler: ->(args, pipeline:) { MASTER::Commands.exit_master; HANDLED } },
    }.freeze

    # Build reverse alias map once at load time: "alias_string" => :canonical_key
    ALIAS_MAP = COMMANDS.each_with_object({}) do |(key, cmd), map|
      (cmd[:aliases] || []).each { |a| map[a.to_s] = key }
    end.freeze

    def lookup(input)
      key = input.to_s.strip.downcase.to_sym
      return COMMANDS[key] if COMMANDS.key?(key)

      canonical = ALIAS_MAP[key.to_s]
      COMMANDS[canonical] if canonical
    end

    def all_aliases
      ALIAS_MAP
    end

    def primary_commands
      COMMANDS.keys
    end

    def groups
      COMMANDS.group_by { |_, v| v[:group] }.transform_values { |cmds| cmds.map(&:first) }
    end
  end
end
