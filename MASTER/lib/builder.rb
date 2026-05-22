# frozen_string_literal: true

require "fileutils"

module Master
  # Single source of truth for container wiring. Each `boot_*` method assembles
  # one subsystem from primitive dependencies. `build` runs them in order.
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE          = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS      = %w[bin lib data].freeze

    TOOL_MAP = {
      "ReadFile"        => ->(r, i) { Reach::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus]) },
      "WriteFile"       => ->(r, i) { Reach::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus], diff_stager: i[:diff_stager]) },
      "StrReplace"      => ->(r, i) { Reach::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus], diff_stager: i[:diff_stager]) },
      "BatchReplace"    => ->(r, i) { Reach::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "AstEdit"         => ->(r, i) { Reach::AstEdit.new(root: r, undo: i[:undo], event_bus: i[:bus]) },
      "Tree"            => ->(r, i) { Reach::Tree.new(root: r, event_bus: i[:bus]) },
      "ListDir"         => ->(r, i) { Reach::ListDir.new(root: r, event_bus: i[:bus]) },
      "SearchFiles"     => ->(r, i) { Reach::SearchFiles.new(root: r, event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Reach::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup"    => ->(r, i) { Reach::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus]) },
      "Shell"           => ->(r, i) { Reach::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "GitContext"      => ->(r, i) { Reach::GitContext.new(root: r, event_bus: i[:bus]) },
      "WebFetch"        => ->(r, i) { Reach::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch"       => ->(r, i) { Reach::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "Clean"           => ->(r, i) { Reach::Clean.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "FeedbackRecord"  => ->(r, i) { Reach::FeedbackRecord.new(learnings: i[:learnings]) },
      "MemoryRecord"    => ->(r, i) { Reach::MemoryRecord.new(memory: i[:memory], root: r, event_bus: i[:bus]) }
    }.freeze

    module_function

    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai    = build_ai(root, infra)
      pipeline, gateway = build_pipeline(root, infra, ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    # No LLM, no autonomous loop, no network. CI / MASTER_SCAN_ONLY=1.
    def build_scan_only(root: Dir.pwd)
      config      = Ground::Config.new(root)
      boot_config = config.freeze_boot
      trace       = boot_trace(root:, config:)
      bus         = trace[:bus]
      code_index  = Judge::CodeIndex.new(root:, event_bus: bus)
      scanner     = build_scanner(root:, bus:)
      trace.merge(config:, boot_config:, code_index:, scanner:, root:)
    end

    def build_infrastructure(root)
      config      = Ground::Config.new(root)
      config["model"] ||= Master.default_model
      boot_config = config.freeze_boot
      trace  = boot_trace(root:, config:)
      loop_c = boot_loop(root:, config:, bus: trace[:bus])
      reach  = boot_reach(root:, config:, bus: trace[:bus])
      ground = boot_ground(root:, config:, homeostat: loop_c[:homeostat])

      bus        = trace[:bus]
      renderer   = Voice::Renderer.new(config:)
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      code_index.build_async
      bus.subscribe("tool:after") do |ev|
        next unless ev[:path] && MUTATING_TOOLS.include?(ev[:tool].to_s)
        code_index.reindex(ev[:path])
      end
      diag     = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging])
      pressure = PressureEngine.new(event_bus: bus)
      bus.subscribe("*") do |ev|
        event_name = ev[:event] || ev["event"] || ev[:type] || ev["type"] || "event"
        next if event_name.to_s.start_with?("pressure:")
        pressure.ingest(event: event_name, payload: ev)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "builder.pressure_engine", event_bus: bus)
      end

      { config:, boot_config:, renderer:, code_index:, diag:, pressure: }
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

    def boot_trace(root:, config:)
      event_log = Trace::EventLog.new(root:)
      bus       = Trace::EventBus.new(event_log:)
      ring      = Trace::RingBuffer.new(RING_SIZE)
      logging   = Trace::Logging.new(ring_buffer: ring, event_bus: bus)
      session   = Trace::Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo      = Trace::Undo.new(session:, event_bus: bus, root:)
      metrics   = Trace::Metrics.new(root:, event_bus: bus)
      Trace::AuditLog.new(root:, event_bus: bus)
      Trace::SwallowLedger.new(event_bus: bus, root:).attach
      recorder  = Trace::Recorder.new(root:, event_bus: bus)
      { event_log:, bus:, ring:, logging:, session:, undo:, metrics:, trace: recorder }
    end

    def boot_loop(root:, config:, bus:)
      homeostat   = Loop::Homeostat.new(event_bus: bus)
      governor    = Loop::Governor.new(config:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? Loop::DiffStager.new(root:, event_bus: bus) : nil
      phase_gates = Ground::PhaseGates.new(root:, event_bus: bus)
      { homeostat:, governor:, diff_stager:, phase_gates: }
    end

    def boot_reach(root:, config:, bus:)
      breaker = Reach::CircuitBreakerRegistry.new(budget_max: config.budget_max, req_max: config.req_max, event_bus: bus)
      cache   = Reach::SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
      mcp     = Reach::McpCoordinator.new(root:, event_bus: bus)
      mcp.connect_all
      { breaker:, cache:, mcp: }
    end

    def boot_ground(root:, config:, homeostat:)
      memory      = Ground::Memory.new(root:)
      personality = Voice::Personality.new(config["persona"]&.to_sym || Voice::Personality::DEFAULT, root:, homeostat:)
      learnings   = Ground::KnowledgeStore.new(root:)
      { memory:, personality:, learnings: }
    end

    def build_ai(root, infra)
      bus   = infra[:bus]
      tools = build_tools(root:, infra:) + infra[:mcp].tools
      deps  = Judge::Agent::Dependencies.from_kwargs(
        config: infra[:config], session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus,
        model_router: Now::Routing::ModelRouter.new(config: infra[:config]),
        reasoning_modes: Judge::Modes.new,
        memory: infra[:memory], personality: infra[:personality],
        code_index: infra[:code_index], homeostat: infra[:homeostat]
      )
      agent    = Judge::Agent.new(deps:)
      soul_doc = Voice::Soul.new(root:, agent:)
      tools << Reach::AskLlm.new(agent:, governor: infra[:governor], circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus)
      ctx = Now::ContextWindow.new(session: infra[:session], agent:, model_context: Master::CTX_WINDOW_SIZE)
      ctx.check_and_compact!
      agent.wire_context_window(ctx)
      agent.wire_constitution(Ground::Constitution.new)
      scanner       = build_scanner(root:, agent:, bus:)
      swarm         = Judge::Swarm::Coordinator.new(agent:, event_bus: bus)
      personas      = Judge::Council::Personas.load(File.join(Master::ROOT, "data", "council.yml"))
      axioms        = Ground::Rules.new(root:)
      deliberation  = Judge::Council::Deliberation.new(personas:, agent:, event_bus: bus, axioms:)
      ideation      = Judge::Council::Ideation.new(agent:, event_bus: bus)
      council_stage = Now::Stages::Council.new(deliberation:, config: infra[:config], event_bus: bus)
      guard         = Judge::Security::InjectionGuard.new
      autonomous    = boot_autonomous(root:, infra:, agent:, scanner:, axioms:)
                        .merge(learnings: infra[:learnings], skills: boot_skills(root, bus))
      autonomous[:standing].wire_container(scanner:, agent:, root:, bus:)
      { agent:, soul: soul_doc, scanner:, swarm:, deliberation:, council_stage:, ideation:, guard: }.merge(autonomous)
    end

    def build_scanner(root:, agent: nil, bus: nil)
      Judge::Scan::RuleDSL
      scanner = Judge::Scan::Scanner.new(event_bus: bus)
      Judge::Scan::Rule.registry.select(&:auto_build?).each { |k| scanner.add_rule(k.new) }
      scanner.add_rule(Judge::Scan::Rules::RuleCoverageRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::InterconnectRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::SemanticRule.new(agent:))
      scanner.add_rule(Judge::Scan::Rules::AdversarialRule.new(agent:))
      scanner.add_rule(Judge::Scan::Rules::CommentDriftRule.new(agent:))
      scanner.add_rule(Judge::Scan::Rules::AstOmissionRule.new(root:))
      scanner
    end

    def boot_autonomous(root:, infra:, agent:, scanner:, axioms: nil)
      bus       = infra[:bus]
      standing  = Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      git       = Reach::GitOperations.new(root)
      rules     = scanner.instance_variable_get(:@rules)
      learnings = infra[:learnings]

      # In-process FixLoop autofix on boot is gated to MASTER_AUTOFIX=1. Off by
      # default — the loop's autocommits race deploys and over-aggressively
      # rewrites framework boilerplate. Run /fix manually or set the env var on
      # hosts where unattended convergence is wanted.
      fix_loop = Loop::FixLoop.new(rules:, axioms:, agent:, scanner:, root:, bus:, git:, learnings:)
      if ENV["MASTER_AUTOFIX"] == "1"
        Thread.new { fix_loop.run_forever(root) }.tap { |t| t.abort_on_exception = false }
      end

      # Architecture #7: reactive file-watcher instead of polling.
      # Activate with MASTER_WATCH=1 on VPS (requires rb-kqueue or rb-inotify).
      watch_loop = if ENV["MASTER_WATCH"] == "1"
        wl = Loop::WatchLoop.new(rules:, agent:, scanner:, root:, bus:, learnings:)
        Thread.new { wl.run }.tap { |t| t.abort_on_exception = false }
        wl
      end

      heartbeat = Loop::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory], event_bus: bus, homeostat: infra[:homeostat])
      triggers  = Trace::Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!

      propose_tree = Loop::ProposeTree.new(root:, agent:, event_bus: bus)
      bus.subscribe("fix_loop:clean")    { Thread.new { propose_tree.call } }
      bus.subscribe("fix_loop:plateau")  { Thread.new { propose_tree.call } }

      # Architecture: continuous OpenBSD load watcher.
      # Default on; MASTER_WATCHER=0 disables. Sampler is read-only.
      watcher = Loop::Watcher.new(bus:, root:)
      if ENV["MASTER_WATCHER"] != "0"
        Thread.new { watcher.run_forever }.tap { |t| t.abort_on_exception = false }
      end
      bus.subscribe("system:crit") { Thread.new { fix_loop.stop_background! if fix_loop.background_alive? } }

      { standing:, fix_loop:, watch_loop:, heartbeat:, triggers:, propose_tree:, watcher: }
    end

    def boot_skills(root, bus)
      skills = Now::Skills.new(root:, event_bus: bus)
      skills.discover!
      skills
    end

    def build_tools(root:, infra:)
      path = File.join(root, "data", "tools.yml")
      defs = Master.load_yaml(path)
      return [] unless defs.is_a?(Array)
      defs.filter_map do |defn|
        next unless defn["default"] == true
        factory = TOOL_MAP[defn["name"].to_s]
        factory ? factory.call(root, infra) : (infra[:bus]&.publish("builder:tool_skipped", tool: defn["name"]); nil)
      end
    end

    def build_pipeline(root, infra, ai)
      config   = infra[:config]
      bus      = infra[:bus]
      commands = Now::CommandRegistry.build(infra:, ai:, root:)
      stages   = [
        Now::Stages::Intake.new,
        Now::Stages::Enhance.new(agent: ai[:agent], event_bus: bus),
        Now::Stages::Infer.new,
        Now::Stages::Route.new(commands:, agent: ai[:agent]),
        Now::Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Now::Stages::Deliberate.new(agent: ai[:agent], config:),
        Now::Stages::Execute.new,
        Now::Pipeline::SkipOnPressure.new(
          Now::Stages::Review.new(council: ai[:council_stage], scanner: ai[:scanner], config:, root:, event_bus: bus),
          bus:
        ),
        Now::Stages::Memory.new(memory: infra[:memory], event_bus: bus),
        Now::Stages::Render.new(renderer: infra[:renderer])
      ]
      pipeline = Now::Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
      ai[:standing].wire_pipeline(pipeline)
      gateway = Reach::Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(_ctx) { gateway.channels }
      [pipeline, gateway]
    end

    def boot_snapshot(container)
      root  = container[:root]
      files = Dir[*SNAPSHOT_DIRS.map { |d| File.join(root, d, "**", "*") }]
               .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
               .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
               .sort
      body = files.flat_map do |f|
        rel  = f.delete_prefix("#{root}/")
        lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src  = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
      rescue StandardError => e
        Ground::Swallow.log(e, context: "builder.snapshot_file", path: f)
        []
      end
      header  = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      content = (header + body).join("\n")
      out     = File.join(root, ".master", "snapshot.md")
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, content)
      File.write(File.join(root, "snapshot.md"), content)
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end
  end
end
