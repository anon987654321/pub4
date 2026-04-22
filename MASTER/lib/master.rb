# frozen_string_literal: true

require "zeitwerk"

module Master
  ROOT = File.expand_path("..", __dir__).freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "autoloop"   => "AutoLoop",
    "cli"        => "CLI",
    "mcp_server" => "MCPServer",
    "llm"        => "LLM",
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.setup

  # Build the full container without starting the CLI
  def self.build(root: Dir.pwd)
    config   = Config.new(root)
    config["model"] ||= default_model

    ring     = RingBuffer.new(1000)
    bus      = EventBus.new(log: ring)
    logging  = Logging.new(ring_buffer: ring, event_bus: bus, trace_level: config.trace)
    session  = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
    undo     = Undo.new(session:, event_bus: bus)
    breaker  = CircuitBreakerRegistry.new(budget_max: config.budget_max, req_max: config.req_max, event_bus: bus)
    cache    = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
    governor = Governor.new(config:, event_bus: bus)
    renderer = Renderer.new(config:)
    metrics  = Metrics.new(root:, event_bus: bus)
    AuditLog.new(root:, event_bus: bus)

    code_index   = CodeIndex.new(root:, event_bus: bus)
    diff_stager  = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
    mcp          = McpCoordinator.new(root:, event_bus: bus)
    mcp.connect_all
    code_index.build # sync on boot (fast: Prism parses ~100 files in <1s)
    bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] rescue nil }

    memory      = Memory.new(root:)
    soul_doc   = Soul.new(root:, agent: nil) # agent wired after agent is built
    personality = Personality.new(config["persona"]&.to_sym || Personality::DEFAULT, root:)

    tools    = build_tools(root:, undo:, governor:, bus:, diff_stager:, code_index:)
    tools   += mcp.tools
    router   = Routing::ModelRouter.new(config:)
    modes    = Reasoning::Modes.new
    agent    = Agent.new(config:, session:, tools:, circuit_breaker: breaker, cache:, event_bus: bus,
                         model_router: router, reasoning_modes: modes,
                         memory:, personality:, code_index:)
    soul_doc.wire_agent(agent)
    tools << Tools::AskLlm.new(agent:, governor:, circuit_breaker: breaker, cache:, event_bus: bus)

    guard        = Security::InjectionGuard.new
    scanner      = Scan::Scanner.new(event_bus: bus)
    scanner.add_rule(Scan::Rules::FrozenStringRule.new)
    scanner.add_rule(Scan::Rules::BareRescueRule.new)
    scanner.add_rule(Scan::Rules::ExplicitRule.new)
    scanner.add_rule(Scan::Rules::ImmutableRule.new)
    scanner.add_rule(Scan::Rules::CqsRule.new)
    scanner.add_rule(Scan::Rules::SelfExplainingRule.new)
    scanner.add_rule(Scan::Rules::LongMethodRule.new)
    scanner.add_rule(Scan::Rules::GodClassRule.new)
    scanner.add_rule(Scan::Rules::DuplicateCodeRule.new)
    scanner.add_rule(Scan::Rules::PruneRule.new)
    scanner.add_rule(Scan::Rules::SrpRule.new)
    scanner.add_rule(Scan::Rules::PolaRule.new)
    scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
    scanner.add_rule(Scan::Rules::ReekRule.new(root:))
    scanner.add_rule(Scan::Rules::NielsenRule.new)
    scanner.add_rule(Scan::Rules::AxiomCoverageRule.new(root:))
    scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
    scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
    swarm        = Swarm::Coordinator.new(agent:, event_bus: bus)
    personas     = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
    deliberation = Council::Deliberation.new(personas:, agent:, event_bus: bus)
    council_stage = Stages::Council.new(deliberation:, config:)

    stages = [
      Stages::Intake.new,
      Stages::Infer.new,
      Stages::Route.new(
        commands: build_commands(session:, undo:, logging:, config:, renderer:, agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, memory:, metrics:),
        agent:
      ),
      Stages::Guard.new(governor:, injection_guard: guard),
      Stages::Execute.new,
      Pipeline::ParallelGroup.new(council_stage, Stages::Lint.new(scanner:, config:)),
      Stages::Prune.new,
      Stages::Memo.new(memory:, event_bus: bus),
      Stages::Render.new(renderer:)
    ]

    ctx_window = ContextWindow.new(session:, agent:, model_context: 200_000)
    ctx_window.check_and_compact!
    agent.instance_variable_set(:@context_window, ctx_window)

    pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true)

    standing = StandingOrders.new(pipeline:, event_bus: bus)

    # Wire orders + soul commands after standing/soul are built (avoids circular dep).
    route_stage = stages.find { |s| s.is_a?(Stages::Route) }
    route_stage&.add_command("orders", ->(ctx) {
  arg = ctx[:args].to_s.strip
  case arg
  when "list", ""
    standing.list
  when /\Aenable (.+)\z/
    standing.enable($1.strip)
  when /\Adisable (.+)\z/
    standing.disable($1.strip)
  when /\Aadd name=(\S+) cmd=(.+)\z/
    standing.upsert(name: $1, command: $2.strip)
  when "run"
    results = standing.run_due!
    results.empty? ? "no orders due" : results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
  when /\Areset (.+)\z/
    standing.reset($1.strip)
  else
      "usage: /orders  /orders enable <name>  /orders disable <name>  /orders reset <name>  /orders run"
    end
    })

    route_stage&.add_command("soul", ->(ctx) {
  arg = ctx[:args].to_s.strip
  case arg
  when "", "show"
    soul_doc.summary
  when "version", "changelog"
    soul_doc.changelog
  when "diff"
    soul_doc.diff
  when "approve"
    soul_doc.approve
  when "reject"
    soul_doc.reject
  when "rollback"
    soul_doc.rollback
  when /\Apropose (.+)\z/
    soul_doc.propose($1.strip)
  else
      "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
    end
    })

    {
      config:, session:, agent:, renderer:, logging:, undo:, pipeline:,
      scanner:, bus:, breaker:, cache:, governor:, metrics:, council_stage:,
      memory:, personality:, swarm:, root:,
      diff_stager:, mcp:, code_index:, standing:, soul: soul_doc,
    }
  end

  # Boot the CLI (wraps build)
  def self.boot(root: Dir.pwd, argv: [])
    container = build(root:)
    container[:renderer].tap { |r| puts r.banner(container[:agent].model) }
    CLI.new(container:)
  end

  def self.default_model
    if ENV["ANTHROPIC_API_KEY"].to_s.length > 10
      "claude-sonnet-4-6"
    elsif ENV["OPENROUTER_API_KEY"].to_s.length > 10
      "anthropic/claude-sonnet-4-6"
    elsif ENV["OPENAI_API_KEY"].to_s.length > 10
      "gpt-4o"
    elsif ENV["GEMINI_API_KEY"].to_s.length > 10
      "gemini-2.5-flash"
    elsif ENV["REPLICATE_API_KEY"].to_s.length > 10
      "deepseek-ai/deepseek-r1"
    else
      raise "No LLM API key found. Set ANTHROPIC_API_KEY, OPENROUTER_API_KEY, or GEMINI_API_KEY."
    end
  end

  def self.build_tools(root:, undo:, governor:, bus:, diff_stager: nil, code_index: nil)
    [
      Tools::ReadFile.new(root:, undo:, event_bus: bus),
      Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus, diff_stager:),
      Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus, diff_stager:),
      Tools::ListDir.new(root:, event_bus: bus),
      Tools::SearchFiles.new(root:, event_bus: bus),
      Tools::WebSearch.new(governor:, event_bus: bus),
      Tools::Shell.new(root:, governor:, event_bus: bus),
      Tools::BatchReplace.new(root:, governor:, event_bus: bus),
      Tools::GitContext.new(root:, event_bus: bus),
      Tools::AstEdit.new(root:, undo:, event_bus: bus),
      Tools::Tree.new(root:, event_bus: bus),
      Tools::SymbolLookup.new(code_index:, event_bus: bus),
      Tools::Clean.new(root:, governor:, event_bus: bus),
      Tools::SearchKnowledge.new(root:, event_bus: bus)
    ]
  end

  def self.build_commands(session:, undo:, logging:, config:, renderer:, agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, memory:, metrics: nil)
    {
      "clear"   => ->(ctx) { session.clear!  ; "context cleared" },
      "save"    => ->(ctx) { session.save!   ; "session saved" },
      "tokens"  => ->(ctx) { "~#{session.token_est} tokens" },
      "undo"    => ->(ctx) { r = undo.undo! ; r.ok? ? "reverted: #{r.value!}" : r.message },
      "dmesg"   => ->(ctx) { logging.dmesg },
      "cost"    => ->(ctx) { "$#{"%.4f" % session.cost}" },
      "config"  => ->(ctx) { config.data.inspect },
      "mode"    => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if Reasoning::Modes::SUPPORTED.include?(arg)
          config["reasoning_mode"] = arg
          config.save!
          "mode: #{arg}"
        else
          "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
        end
      },
      "task"    => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg.empty?
          "task_type: #{config.task_type}"
        else
          config["task_type"] = arg
          config.save!
          "task_type: #{arg}"
        end
      },
      "autotest" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        case arg
        when "on"  then config["auto_testing"] = true;  config.save!; "autotest: on"
        when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
        else "autotest: #{config.auto_testing? ? "on" : "off"}"
        end
      },
      "council" => ->(ctx) {
        case ctx[:args].to_s.strip
        when "on"  then council_stage.enable!  ; "council: enabled"
        when "off" then council_stage.disable! ; "council: disabled"
        else "council: #{council_stage.instance_variable_get(:@enabled) ? "on" : "off"}"
        end
      },
      "swarm" => ->(ctx) {
        args = ctx[:args].to_s.strip.split(" ", 2)
        role, task = args[0]&.to_sym, args[1].to_s
        if role.nil? || task.empty?
          "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}"
        else
          dispatch_result = swarm.dispatch(role, task: task, context_slice: {})
          dispatch_result.ok? ? dispatch_result.value!.inspect : dispatch_result.message
        end
      },
"explain" => ->(ctx) {
  map  = Introspection::SelfMap.new(root:)
  info = map.describe
  cov  = map.axiom_coverage
  cov_lines = cov.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
  stages = "Intake→Infer→Route→Guard→Execute→Council→Lint→Prune→Memo→Render"
  "MASTER — #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov_lines}"
},
"persona" => ->(ctx) {
  arg   = ctx[:args].to_s.strip.to_sym
  names = Personality::PERSONAS.keys
  if names.include?(arg)
    config["persona"] = arg.to_s
    config.save!
    "persona: #{arg}"
  else
    "persona: #{config["persona"] || "dark_malay"} — available: #{names.join(", ")}"
  end
},
"autoloop" => ->(ctx) {
      max    = ctx[:args].to_s.strip.to_i
      max    = AutoLoop::MAX_CYCLES if max <= 0
      looper = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
      log    = []
      result = looper.run(max_cycles: max) { |cycle, violations|
        log << "  cycle #{cycle}: #{violations.size} violation(s)"
      }
      ([result.ok? ? result.value! : result.message] + log).join("\n")
    },
    "sweep" => ->(ctx) {

        arg     = ctx[:args].to_s.strip
        target  = arg.empty? ? root : File.expand_path(arg, root)
        sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        log     = []
        result  = sweeper.run(target) { |cycle, file, delta|
          log << "  cycle #{cycle}  #{file}  +#{delta}"
        }
        ([result.ok? ? result.value! : result.message] + log).join("\n")
      },
      "memory"  => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg.start_with?("forget ")
          key = arg.sub("forget ", "").strip
          memory.forget(key)
          "forgot: #{key}"
        elsif arg.start_with?("remember ")
          parts = arg.sub("remember ", "").split("=", 2)
          key, val = parts[0].strip, parts[1]&.strip
          val ? (memory.remember(key, val); "remembered: #{key}") : "usage: /memory remember key=value"
        elsif arg.start_with?("search ")
          query = arg.sub("search ", "").strip
          hits  = memory.respond_to?(:semantic_recall) ? memory.semantic_recall(query) : memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
          hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
        elsif arg.empty?
          entries = memory.all
          entries.empty? ? "(no memories)" : entries.map { |k, v| "#{k}: #{v}" }.join("\n")
        else
          val = memory.recall(arg)
          val ? "#{arg}: #{val}" : "(not found: #{arg})"
        end
      },
      "dreams" => ->(ctx) {
      arg = ctx[:args].to_s.strip
      if arg == "consolidate"
        memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
      else
        entries = memory.all
        archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
        active   = entries.count { |k, _| !k.to_s.start_with?("archive/") }
        summary  = memory.recall("_consolidated_summary")
        lines    = ["active: #{active} memories, archived: #{archived}"]
        lines   << "last consolidation: #{summary}" if summary
        lines.join("\n")
      end
    },
    "snapshot" => ->(ctx) {
        stamp  = Time.now.strftime("%Y%m%d_%H%M%S")
        out    = File.expand_path("~/master_snapshot_#{stamp}.md")
        lang_map = { ".rb" => "ruby", ".yml" => "yaml", ".yaml" => "yaml",
                     ".js" => "javascript", ".json" => "json", ".sh" => "bash",
                     ".zsh" => "bash", ".md" => "markdown", ".html" => "html",
                     ".erb" => "erb", ".css" => "css" }
        dirs   = %w[exe lib/master web/app web/config data].map { |d| File.join(root, d) }
        files  = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                   .select { |f| File.file?(f) && File.size(f) < 200_000 }
                   .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                   .reject { |f| File.binread(f, 512).include?("\x00") rescue true }
                   .sort

        lines  = ["# MASTER Codebase Snapshot", "Generated: #{Time.now.utc.iso8601}", ""]
        files.each do |f|
          rel  = f.sub("#{root}/", "")
          lang = lang_map.fetch(File.extname(f).downcase, "text")
          src  = File.read(f, encoding: "UTF-8", invalid: :replace)
          lines << "## #{rel}" << "```#{lang}" << src.rstrip << "```" << ""
        rescue StandardError => e
          lines << "## #{rel}" << "[skipped: #{e.message}]" << ""
        end

        File.write(out, lines.join("\n"))
        "snapshot: #{files.size} files written to #{out}"
      },
"cache" => ->(ctx) {
  arg = ctx[:args].to_s.strip
  if arg == "clear"
    cache.invalidate_all!
    "cache cleared"
  elsif arg == "stats"
    s = cache.stats
    "cache: #{s[:entries]} entries, #{s[:size_kb]} KB"
  else
    s = cache.stats
    "cache: #{s[:entries]} entries, #{s[:size_kb]} KB  (use /cache clear to purge)"
  end
},
"diff" => ->(ctx) {
  arg  = ctx[:args].to_s.strip
  base = arg.empty? ? "HEAD" : arg
  out  = `git -C #{root.shellescape} diff #{base} --stat 2>&1`.strip
  out.empty? ? "(no changes since #{base})" : out
},
"model" => ->(ctx) {
  arg = ctx[:args].to_s.strip
  if arg == "list"
    yml_path = File.join(root, "data", "models.yml")
    if File.exist?(yml_path)
      require "yaml"
      data = YAML.safe_load_file(yml_path)
      tiers = data["models"] || {}
      model_lines = tiers.flat_map { |tier, ms| ms.to_a.map { |m| "  [#{tier}] #{m["id"]}" } }
      quality_lines = metrics&.model_quality&.map do |mod, s|
        "  #{mod}: #{s[:calls]} calls, fail_rate=#{s[:fail_rate]}"
      end || []
      sections = ["available models:"] + model_lines
      sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
      sections.join("\n")
    else
      "model: #{agent.model}"
    end
  elsif arg.empty?
    "model: #{agent.model}"
  else
    agent.instance_variable_set(:@model, arg)
    config["model"] = arg
    config.save!
    "model: #{arg}"
  end
},
"commit" => ->(ctx) {
  diff = `git -C #{root.shellescape} diff --cached --stat 2>&1`.strip
  diff = `git -C #{root.shellescape} diff --stat 2>&1`.strip if diff.empty?
  return "nothing to commit" if diff.empty?
  prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
  msg    = agent.ask_once(prompt)
  msg    = msg.strip.lines.first.to_s.strip.gsub(/"/, "'")
  out    = `git -C #{root.shellescape} add -u 2>&1 && git -C #{root.shellescape} commit -m "#{msg}" 2>&1`.strip
  out
},
"knowledge" => ->(ctx) {
  arg = ctx[:args].to_s.strip
  if arg.start_with?("add ")
    url = arg.sub("add ", "").strip
    require "open-uri"
    require "shellwords"
    return "usage: /knowledge add <url>" if url.empty?
    slug    = url.gsub(/[^a-z0-9._-]/i, "_").downcase[0, 60]
    kdir    = File.join(root, "knowledge", "web")
    FileUtils.mkdir_p(kdir)
    dest    = File.join(kdir, "#{slug}.txt")
    content = URI.open(url, read_timeout: 15, &:read).encode("UTF-8", invalid: :replace, undef: :replace)
    File.write(dest, content, encoding: "UTF-8")
    "saved #{content.bytesize} bytes to knowledge/web/#{slug}.txt"
  else
    "usage: /knowledge add <url>"
  end
},
"why" => ->(ctx) {
  rule = ctx[:args].to_s.strip
  if rule.empty?
    "usage: /why <rule_name>  -- explains a scan rule. e.g. /why ExplicitRule"
  else
    prompt = "Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
             "give a before/after Ruby example, and state why it matters."
    agent.ask_once(prompt)
  end
},
"scan" => ->(ctx) {
  depth  = ctx[:args].to_s.include?("deep") ? :deep : :standard
  target = File.join(root, "lib")
  result = scanner.scan_dir(target, depth:)
  unless result.respond_to?(:ok?) && result.ok?
    next "scan failed"
  end
  by_rule = Hash.new { |h, k| h[k] = [] }
  result.value!.each do |_f, fr|
    next unless fr.respond_to?(:ok?) && fr.ok?
    fr.value!.each { |v| by_rule[v[:rule].to_s] << v }
  end
  total = by_rule.values.sum(&:size)
  next "clean -- no violations" if total.zero?
  lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
    ["[#{rule}] #{vs.size}"] + vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, 90]}" }
  end
  lines << "#{total} total violations"
  lines.join("\n")
},
      "help"    => ->(ctx) {
        cmds = %w[clear save tokens undo dmesg cost config model mode task autotest council autoloop swarm sweep memory dreams orders soul cache diff commit knowledge why snapshot explain persona help exit]
        cmds.map { "/#{_1}" }.join("  ")
      }
    }
  end
end