# frozen_string_literal: true

module MASTER
  # CommandRegistry - single source of truth for command metadata AND dispatch.
  # Each entry carries a handler lambda called as handler.call(args, pipeline:).
  # Returning MASTER::Commands::HANDLED means "printed output, no Result needed".
  # Returning nil means "unknown — fall through to LLM".
  module CommandRegistry
    module_function

    COMMANDS = {
      refactor:         { desc: "Refactor a file with 6-phase analysis", usage: "refactor <file>",                group: :query,    aliases: %w[autofix],
                          handler: ->(args, pipeline:) { MASTER::Commands.autofix(args) } },
      chamber:          { desc: "Multi-model deliberation",            usage: "chamber <file>",                   group: :query,
                          handler: ->(args, pipeline:) { MASTER::Commands.chamber(args) } },
      evolve:           { desc: "Self-improvement cycle",              usage: "evolve [path]",                    group: :query,
                          handler: ->(args, pipeline:) { MASTER::Commands.evolve(args) } },
      opportunities:    { desc: "Find improvements",                   usage: "opportunities [path]",             group: :query,    aliases: %w[opps],
                          handler: ->(args, pipeline:) { MASTER::Commands.opportunities(args) } },
      scan:             { desc: "Scan for code smells",                usage: "scan [path] [--debug|--critique]", group: :analysis, aliases: %w[debug hunt critique conflict],
                          handler: ->(args, pipeline:) { MASTER::Commands.scan_code(args);    MASTER::Commands::HANDLED } },
      learn:            { desc: "Show matching learned patterns",      usage: "learn <file>",                     group: :analysis,
                          handler: ->(args, pipeline:) { MASTER::Commands.show_learnings(args); MASTER::Commands::HANDLED } },
      fix:              { desc: "Fix violations in file or directory", usage: "fix [path]",                      group: :analysis,
                          handler: ->(args, pipeline:) { MASTER::Commands.fix_code(args);     MASTER::Commands::HANDLED } },
      converge:         { desc: "Iterate until violations plateau",    usage: "converge [max_iter]",              group: :analysis,
                          handler: ->(args, pipeline:) { MASTER::Commands.run_converge(args) } },
      "multi-refactor": { desc: "Refactor directory",                  usage: "multi-refactor [path]",            group: :analysis, aliases: %w[mrefactor],
                          handler: ->(args, pipeline:) { MASTER::Commands.multi_refactor(args) } },
      "self-fix":       { desc: "Scan, fix, and commit MASTER2 itself", usage: "self-fix [--dry-run]",             group: :analysis, aliases: %w[selfrun self-run selftest self-test self],
                          handler: ->(args, pipeline:) { MASTER::Commands.self_run(args) } },
      session:          { desc: "Session management",                  usage: "session [new|save|load]",          group: :session,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_session(args); MASTER::Commands::HANDLED } },
      sessions:         { desc: "List saved sessions",                 usage: "sessions",                         group: :session,
                          handler: ->(args, pipeline:) { MASTER::Commands.print_saved_sessions; MASTER::Commands::HANDLED } },
      forget:           { desc: "Undo last exchange",                  usage: "forget",                           group: :session,  aliases: %w[undo],
                          handler: ->(args, pipeline:) { MASTER::Commands.undo_last_exchange;  MASTER::Commands::HANDLED } },
      summary:          { desc: "Conversation summary",                usage: "summary",                          group: :session,
                          handler: ->(args, pipeline:) { MASTER::Commands.print_session_summary; MASTER::Commands::HANDLED } },
      capture:          { desc: "Capture session insights",            usage: "capture",                          group: :session,  aliases: %w[session-capture],
                          handler: ->(args, pipeline:) { MASTER::Commands.session_capture;     MASTER::Commands::HANDLED } },
      "review-captures": { desc: "Review captured insights",          usage: "review-captures",                  group: :session,
                          handler: ->(args, pipeline:) { MASTER::Commands.review_captures;     MASTER::Commands::HANDLED } },
      recent:           { desc: "Show recent commands",                usage: "recent",                           group: :session,
                          handler: ->(args, pipeline:) { MASTER::Commands.show_recent_commands; MASTER::Commands::HANDLED } },
      status:           { desc: "System status",                       usage: "status",                           group: :system,
                          handler: ->(args, pipeline:) { MASTER::Dashboard.new.render;         MASTER::Commands::HANDLED } },
      budget:           { desc: "Budget remaining",                    usage: "budget",                           group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.print_budget;        MASTER::Commands::HANDLED } },
      context:          { desc: "Context window usage",                usage: "context",                          group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.show_project_context; MASTER::Commands::HANDLED } },
      history:          { desc: "Cost history",                        usage: "history",                          group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.print_cost_history;  MASTER::Commands::HANDLED } },
      health:           { desc: "Health check and diagnostics",          usage: "health [--deep|--setup]",          group: :system,   aliases: %w[doctor bootstrap],
                          handler: ->(args, pipeline:) { MASTER::Commands.print_health(args);   MASTER::Commands::HANDLED } },
      "history-dig":    { desc: "Recover deleted historical file",     usage: "history-dig [file]",               group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.history_dig(args);   MASTER::Commands::HANDLED } },
      codify:           { desc: "Show/export codified design rules",   usage: "codify [export-json]",             group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.codify(args);        MASTER::Commands::HANDLED } },
      "style-guides":   { desc: "List/sync style guides",              usage: "style-guides [sync]",              group: :system,   aliases: %w[styleguides],
                          handler: ->(args, pipeline:) { MASTER::Commands.style_guides(args);  MASTER::Commands::HANDLED } },
      "axioms-stats":   { desc: "Axiom violation statistics",          usage: "axioms-stats",                     group: :system,   aliases: %w[stats],
                          handler: ->(args, pipeline:) { MASTER::Commands.print_axiom_stats;   MASTER::Commands::HANDLED } },
      axioms:           { desc: "Language axioms",                     usage: "axioms",                           group: :system,   aliases: %w[language-axioms],
                          handler: ->(args, pipeline:) { MASTER::Commands.print_language_axioms(args); MASTER::Commands::HANDLED } },
      deps:             { desc: "Dependency map",                      usage: "deps [file]",                      group: :system,   aliases: %w[who-requires],
                          handler: ->(args, pipeline:) { MASTER::Commands.print_deps(args);    MASTER::Commands::HANDLED } },
      introspect:       { desc: "Friction and retrospective report",   usage: "introspect",                       group: :system,   aliases: %w[retrospect friction],
                          handler: ->(args, pipeline:) { MASTER::Commands.print_introspection(args); MASTER::Commands::HANDLED } },
      "config-drift":   { desc: "Config drift analysis",               usage: "config-drift",                     group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.print_config_drift;  MASTER::Commands::HANDLED } },
      architect:        { desc: "Architecture overview",               usage: "architect",                        group: :system,   aliases: %w[arch architecture],
                          handler: ->(args, pipeline:) { MASTER::Commands.print_architect;     MASTER::Commands::HANDLED } },
      "init-instructions": { desc: "Regenerate CLAUDE.md / copilot instructions", usage: "init-instructions [--force]", group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.init_instructions(force: args.to_s.include?("--force")); MASTER::Commands::HANDLED } },
      schedule:         { desc: "Job scheduler",                       usage: "schedule <cmd>",                   group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_schedule(args) } },
      heartbeat:        { desc: "Heartbeat control",                   usage: "heartbeat <cmd>",                  group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_heartbeat(args) } },
      policy:           { desc: "Policy profile management",           usage: "policy [set <profile>]",           group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_policy(args) } },
      goal:             { desc: "Project goal",                        usage: "goal [text]",                      group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.project_goal(args);  MASTER::Commands::HANDLED } },
      remember:         { desc: "Remember project note",               usage: "remember <text>",                  group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.project_remember(args); MASTER::Commands::HANDLED } },
      "forget-goal":    { desc: "Clear project goal",                  usage: "forget-goal",                      group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.project_forget;      MASTER::Commands::HANDLED } },
      snapshot:         { desc: "Project snapshot",                    usage: "snapshot",                         group: :system,   aliases: %w[showp],
                          handler: ->(args, pipeline:) { MASTER::Commands.run_snapshot(args);  MASTER::Commands::HANDLED } },
      "webtest":        { desc: "Web test runner",                     usage: "webtest [url]",                    group: :system,   aliases: %w[web-test],
                          handler: ->(args, pipeline:) { MASTER::Commands.run_webtest(args);   MASTER::Commands::HANDLED } },
      cache:            { desc: "Semantic cache stats",                usage: "cache [stats|clear]",              group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.show_cache_stats(args); MASTER::Commands::HANDLED } },
      model:            { desc: "Select LLM model",                    usage: "model <name>",                     group: :system,   aliases: %w[use],
                          handler: ->(args, pipeline:) { MASTER::Commands.select_model(args);  MASTER::Commands::HANDLED } },
      models:           { desc: "List models",                         usage: "models",                           group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.list_models;         MASTER::Commands::HANDLED } },
      pattern:          { desc: "Select executor pattern",             usage: "pattern <name>",                   group: :system,   aliases: %w[mode],
                          handler: ->(args, pipeline:) { MASTER::Commands.select_pattern(args); MASTER::Commands::HANDLED } },
      patterns:         { desc: "List executor patterns",              usage: "patterns",                         group: :system,   aliases: %w[modes],
                          handler: ->(args, pipeline:) { MASTER::Commands.list_patterns;       MASTER::Commands::HANDLED } },
      persona:          { desc: "Manage active persona",               usage: "persona <name|off>",               group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_persona(args); MASTER::Commands::HANDLED } },
      personas:         { desc: "List personas",                       usage: "personas",                         group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.list_personas;       MASTER::Commands::HANDLED } },
      workflow:         { desc: "Workflow control",                    usage: "workflow <cmd>",                   group: :system,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_workflow(args); MASTER::Commands::HANDLED } },
      ideate:           { desc: "Generate alternatives for a topic",   usage: "ideate <topic>",                   group: :query,    aliases: %w[brainstorm],
                          handler: ->(args, pipeline:) { MASTER::Commands.ideate(args) } },
      creative:         { desc: "Creative chamber",                    usage: "creative <prompt>",                group: :query,
                          handler: ->(args, pipeline:) { MASTER::Commands.creative_chamber(args); MASTER::Commands::HANDLED } },
      chat:             { desc: "Focused chat mode",                   usage: "chat [topic]",                     group: :query,
                          handler: ->(args, pipeline:) { MASTER::Commands.enter_chat_mode(args); MASTER::Commands::HANDLED } },
      web:              { desc: "Start web server",                    usage: "web [port]",                       group: :util,     aliases: %w[server],
                          handler: ->(args, pipeline:) { MASTER::Commands.start_web_server(args); MASTER::Commands::HANDLED } },
      speak:            { desc: "Text-to-speech",                      usage: "speak <text>",                     group: :util,     aliases: %w[say],
                          handler: ->(args, pipeline:) { MASTER::Commands.speak(args);         MASTER::Commands::HANDLED } },
      browse:           { desc: "Browse and extract web content",      usage: "browse <url>",                     group: :util,
                          handler: ->(args, pipeline:) { MASTER::Commands.browse_url(args);    MASTER::Commands::HANDLED } },
      queue:            { desc: "Queue operations",                    usage: "queue <cmd>",                      group: :util,
                          handler: ->(args, pipeline:) { MASTER::Commands.manage_queue(args);  MASTER::Commands::HANDLED } },
      harvest:          { desc: "Data harvesting",                     usage: "harvest <target>",                 group: :util,
                          handler: ->(args, pipeline:) { MASTER::Commands.harvest_data(args);  MASTER::Commands::HANDLED } },
      replicate:        { desc: "Generate media via Replicate",        usage: "replicate <prompt>",               group: :util,     aliases: %w[repligen generate-image generate-video],
                          handler: ->(args, pipeline:) { MASTER::Commands.replicate_command("replicate", args); MASTER::Commands::HANDLED } },
      narrate:          { desc: "Generate narrated video demo",        usage: "narrate [--segments]",             group: :util,     aliases: %w[narration],
                          handler: ->(args, pipeline:) { MASTER::Commands.narrate_command(args); MASTER::Commands::HANDLED } },
      postpro:          { desc: "Post-processing operations",          usage: "postpro <op> <path|url>",          group: :util,     aliases: %w[enhance upscale],
                          handler: ->(args, pipeline:) { MASTER::Commands.postpro_command("postpro", args); MASTER::Commands::HANDLED } },
      shell:            { desc: "Interactive shell",                   usage: "shell",                            group: :util,
                          handler: ->(args, pipeline:) { MASTER::InteractiveShell.new.run;     MASTER::Commands::HANDLED } },
      clear:            { desc: "Clear screen",                        usage: "clear",                            group: :util,
                          handler: ->(args, pipeline:) { print "\e[2J\e[H";                    MASTER::Commands::HANDLED } },
      help:             { desc: "Show this help",                      usage: "help [command]",                   group: :util,     aliases: %w[?],
                          handler: ->(args, pipeline:) { MASTER::Help.show(args);              MASTER::Commands::HANDLED } },
      version:          { desc: "Show version",                        usage: "version",                          group: :util,     aliases: %w[ver --version -v],
                          handler: ->(args, pipeline:) { puts "MASTER #{MASTER::VERSION}";     MASTER::Commands::HANDLED } },
      exit:             { desc: "Exit MASTER",                         usage: "exit",                             group: :util,     aliases: %w[quit],
                          handler: ->(args, pipeline:) { :exit } },
    }.freeze

    # Examples for key commands — shown by help <command> and command?
    EXAMPLES = {
      refactor:         "refactor lib/pipeline.rb",
      scan:             "scan lib/ --debug",
      fix:              "fix --all",
      chamber:          "chamber lib/master.rb",
      self:             "self --dry-run",
      health:           "health --deep",
      session:          "session save milestone-1",
      evolve:           "evolve lib/",
      browse:           "browse https://example.com",
      speak:            "speak hello world",
      model:            "model gpt-4o",
      "multi-refactor": "multi-refactor lib/ --apply",
      ideate:           "ideate authentication system",
    }.freeze

    # Flat alias → canonical key map, built once.
    ALIAS_MAP = COMMANDS.each_with_object({}) do |(key, meta), map|
      map[key.to_s] = key
      (meta[:aliases] || []).each { |a| map[a] = key }
    end.freeze

    # When an alias needs to inject flags (e.g. "debug" → "scan --hunt")
    ALIAS_FLAGS = {
      "debug"     => "--hunt",
      "hunt"      => "--hunt",
      "critique"  => "--critique",
      "conflict"  => "--critique",
      "doctor"    => "--deep",
      "bootstrap" => "--setup",
    }.freeze

    # Look up and call the handler for +cmd+. Returns nil if unknown.
    def dispatch(cmd, args, pipeline:)
      key = ALIAS_MAP[cmd.to_s.downcase]
      return nil unless key

      flag = ALIAS_FLAGS[cmd.to_s.downcase]
      args = "#{args} #{flag}".strip if flag

      COMMANDS[key][:handler].call(args, pipeline: pipeline)
    end

    # Meta-ops: commands that stay as % sigil shortcuts, never sent through LLM tool-call
    META_OPS = %i[help version exit clear status budget context history model models
                  pattern patterns persona personas undo forget sessions].to_set.freeze

    # Generate RubyLLM::Tool subclasses from non-meta commands.
    # LLM can invoke these as tool-calls instead of user typing command names.
    def to_tool_classes
      COMMANDS.filter_map do |key, meta|
        next if META_OPS.include?(key)

        cmd_name = key.to_s
        cmd_desc = meta[:desc]
        # Build a dynamic RubyLLM::Tool subclass
        Class.new(RubyLLM::Tool) do
          @cmd_key = cmd_name
          description "MASTER command: #{cmd_desc}"
          param :args, desc: "Arguments for '#{cmd_name}' (e.g. file path, flags)", required: false

          class << self
            attr_reader :cmd_key
          end

          define_method(:execute) do |args: ""|
            pipeline = Thread.current[:repl_pipeline]
            MASTER::CommandRegistry.dispatch(self.class.cmd_key, args, pipeline: pipeline)
          end
        end
      end
    end

    def help_commands
      COMMANDS.transform_values { |v| v.slice(:desc, :usage, :group) }
    end

    def primary_commands
      COMMANDS.keys.map(&:to_s)
    end

    def autocomplete_commands
      ALIAS_MAP.keys.uniq
    end
  end
end
