# MASTER Snapshot — lib/master/
Generated: 2026-05-04T10:21:42Z

## lib/master/agent.rb
```ruby
# frozen_string_literal: true

require "ruby_llm"
require "digest"
require_relative "agent/llm_dispatch"

module Master
  class Agent
    include LlmDispatch

    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN = 0.000_015

    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE = build_tool_capable_re.freeze
    MAX_TOOL_TURNS = 5
    TOOL_CALL_RE = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze
    NEMOTRON3_RE = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    LLM_TOOL_MAP = {
      Tools::ReadFile        => Tools::LLM::ReadFile,
      Tools::WriteFile       => Tools::LLM::WriteFile,
      Tools::StrReplace      => Tools::LLM::StrReplace,
      Tools::ListDir         => Tools::LLM::ListDir,
      Tools::SearchFiles     => Tools::LLM::SearchFiles,
      Tools::Shell           => Tools::LLM::Shell,
      Tools::WebSearch       => Tools::LLM::WebSearch,
      Tools::AskLlm          => Tools::LLM::AskLlm,
      Tools::GitContext      => Tools::LLM::GitContext,
      Tools::AstEdit         => Tools::LLM::AstEdit,
      Tools::SearchKnowledge => Tools::LLM::SearchKnowledge
    }.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil, context_window: nil)
      @config, @session, @tools          = config, session, tools
      @circuit_breaker, @cache, @bus     = circuit_breaker, cache, event_bus
      @model_router, @reasoning_modes    = model_router, reasoning_modes
      @memory, @personality, @code_index = memory, personality, code_index
      @context_window                    = context_window
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt = apply_reasoning_mode(message)
      context = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / Session::TOKENS_PER_CHAR)

      begin
        @circuit_breaker.check_rate!
      rescue CircuitBreaker::CircuitError => rate_err
        return Result.err(rate_err.message, category: rate_err.category)
      end

      last_response = attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      return last_response if last_response.respond_to?(:err?) && last_response.err?
      last_response = maybe_escalate(last_response, message, stream:, escalation_depth:, &blk)

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :handler_exception)
    end

    def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = routed_models.first
      result = send_with_cache(selected_model, messages, stream: false)
      raise result.message if result.respond_to?(:err?) && result.err?
      result.to_s
    end

    def ask_once(prompt, system: nil, model: nil)
      result = send_with_cache(model || self.model, [{ role: "user", content: prompt.to_s }], system:, stream: false)
      result.is_a?(String) ? result : (result.ok? ? result.value!.to_s : "")
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first
    def model=(val)
      @config["model"] = val
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary if @code_index&.built?
      parts << @memory.context_summary if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end
  end
end

```

## lib/master/audit_log.rb
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only tool invocation log; subscribes to tool:before on EventBus.
  class AuditLog
    LOG_PATH = ".master/audit.log".freeze
    MAX_VAL  = 120

    def initialize(root:, event_bus:)
      @path  = File.join(root, LOG_PATH)
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(@path))
      event_bus.subscribe("tool:before") { |event_data| append(event_data) }
    end

    private

    def append(event_data)
      payload_pairs = event_data.except(:tool)
                                .map { |k, v| "#{k}=#{v.to_s[0, MAX_VAL].inspect}" }
                                .join(" ")
      log_line = "#{Time.now.utc.iso8601} tool=#{event_data[:tool]} #{payload_pairs}"
      @mutex.synchronize { File.open(@path, "a") { |f| f.puts(log_line) } }
    end
  end
end

```

## lib/master/autoloop.rb
```ruby
# frozen_string_literal: true

require "open3"
require_relative "git_operations"

require_relative "autoloop/fix_evaluator"

module Master
  class AutoLoop
    def self.load_cfg
      Master.load_yaml(File.join(Master::ROOT, "data", "workflow.yml"))
            .dig("autoloop") || {}
    rescue StandardError => _e
      {}
    end

    _cfg = load_cfg
    MAX_CYCLES           = _cfg.fetch("max_cycles",           12)
    BATCH_SIZE           = _cfg.fetch("batch_size",            3)
    RATE_LIMIT_SLEEP     = _cfg.fetch("rate_limit_sleep",     15)
    MAX_FIX_RETRIES      = _cfg.fetch("max_fix_retries",       3)
    CONFIDENCE_THRESHOLD = _cfg.fetch("confidence_threshold", 0.60)
    MAX_FILE_BYTES       = _cfg.fetch("max_file_bytes",   16_000)
    SKIP_RULES           = Array(_cfg.fetch("skip_rules", [])).freeze
    TARGETS              = Array(_cfg.fetch("targets", %w[lib/ test/ data/ web/ DEPLOY/])).freeze
    EXCLUDES             = Array(_cfg.fetch("excludes", %w[vendor/ knowledge/])).freeze

    SCORE_INCREMENT = 0.25
    MAX_SIZE_RATIO  = 2.0
    MIN_SIZE_RATIO  = 0.80

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil, learnings: nil)
      @agent           = agent
      @scanner         = scanner
      @root            = root
      @bus             = event_bus
      @soul            = soul
      @learnings       = learnings
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git             = GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_paths  = TARGETS.map { |d| File.join(@root, d.delete_suffix("/")) }
                              .select { |d| File.directory?(d) }
        all_results = scan_paths.flat_map { |dir|
          scan_result = @scanner.scan_dir(dir, depth: :standard)
          scan_result.ok? ? scan_result.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        # Deduplicate by file — one fix per unique file to avoid write-race.
        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)

        mutex   = Mutex.new
        fixes   = {}
        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota

        threads = by_file.each_with_index.map do |v, idx|
          Thread.new do
            sleep(stagger * idx) if idx.positive?
            fix = request_fix(v)
            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix
          rescue StandardError => e
            @bus&.publish("autoloop:thread_error", file: v[:file], error: e.message)
          end
        end
        threads.each(&:join)

        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }

        if @git.dirty?("lib/")
          @git.add_lib_files
          @git.commit("autoloop: fix scan violations [cycle #{cycle}]")
          if @learnings
            fixes.each_value { |v, _| @learnings.record(trigger: v[:rule].to_s, strategy: "autoloop_fix", outcome: "commit") }
          end
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    include FixEvaluator
    private

    def apply_fix(rel_path, fixed_src)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)
      original = File.read(path, encoding: "UTF-8")
      return if fixed_src.strip == original.strip
      temporary_path = "#{path}.tmp.#{Process.pid}"
      File.write(temporary_path, fixed_src)
      File.rename(temporary_path, path)
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    rescue StandardError => e
      @bus&.publish("autoloop:write_error", file: rel_path, error: e.message)
    end

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.ok?
        rel = path.delete_prefix("#{@root}/")
        next [] if EXCLUDES.any? { |ex| rel.start_with?(ex) }
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .reject { |f| SKIP_RULES.include?(f[:rule].to_s) }
          .map    { |f| f.merge(file: rel) }
      }.select { |f|
        full_path = File.join(@root, f[:file])
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES # GUARD_EXPENSIVE
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return nil
      end

      src         = File.read(path, encoding: "UTF-8")
      base_prompt = build_fix_prompt(violation, src)
      result = Reflexion.run(agent: @agent, task: base_prompt, max: MAX_FIX_RETRIES) do |prompt, attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          fix = extract_code(@agent.ask(prompt).to_s)
          next nil if fix.nil?
          next nil if confidence_score(fix, src) < CONFIDENCE_THRESHOLD
          fix
        rescue StandardError => e
          err = e.message.to_s
          if TRANSIENT_RE.match?(err) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: err[0, 120])
          end
          nil
        end
      end
      result.respond_to?(:ok?) && result.ok? ? result.value! : nil
    end
  end
end

```

## lib/master/axioms.rb
```ruby
# frozen_string_literal: true

module Master
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
  class Axioms
    DATA_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "rules.yml").freeze
    WORKFLOW_PATH = File.join(File.expand_path("../../..", __dir__), "data", "workflow.yml").freeze

    def initialize(root: nil)
      @rules_path    = root ? File.join(root, "data", "rules.yml")    : DATA_PATH
      @workflow_path = root ? File.join(root, "data", "workflow.yml") : WORKFLOW_PATH
      @data          = load_yaml(@rules_path)    || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end

    def kernel
      @kernel ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .select { |r| r["tier"] == "kernel" }
          .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
          .freeze
      end
    end

    def workflow = @workflow.freeze

    def philosophy(limit: nil)
      @philosophy ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .reject { |r| r["tier"] == "kernel" }
          .map { |h| h.transform_keys(&:to_s) }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end

    def all_rules     = @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    def rules_for_scope(scope) = (@data.dig("rules", scope.to_s) || []).freeze

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Rules (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return nil if items.empty?

      top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
      "## Rules (top #{items.size})\n#{top}"
    end

    def voice    = @voice    ||= (@data["voice"] || {}).freeze
    def strunk   = @strunk   ||= (voice["strunk"] || {}).freeze
    def preserve = @preserve ||= (voice["preserve"] || {}).freeze

    def constitution
      @constitution ||= begin
        constitution_data = {}
        constitution_data["golden_rule"]         = @data["golden_rule"]
        constitution_data["protection"]          = @data["protection"]
        constitution_data["banned_output"]       = voice["banned_output"]
        constitution_data["anti_simulation"]     = voice["anti_simulation"]
        constitution_data["communication_style"] = voice["style"]
        constitution_data.freeze
      end
    end

    def thresholds       = @thresholds       ||= (@data["thresholds"] || {}).freeze
    def scan_depths      = @scan_depths      ||= (@data["scan_depths"] || {}).freeze
    def languages_config = @languages_config ||= (@data["languages"] || {}).freeze
    def workflow_rule(key) = @workflow.dig(key.to_s) || {}

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
    end

    def valid_id?(id) = all_ids.include?(id.to_s)
    def all_ids       = @all_ids ||= all_rules.map { |r| r["id"] }.compact.to_set.freeze
    def empty?        = @data.empty?

    private

    def load_yaml(path)
      return nil unless File.exist?(path)

      Master.load_yaml(path)
    rescue StandardError => _e
      nil
    end
  end
end

```

## lib/master/bedrock_stub.rb
```ruby
# frozen_string_literal: true

# Pre-define Bedrock constants before ruby_llm loads.
# Zeitwerk skips autoloading already-defined constants, so bedrock/auth.rb
# (which requires openssl.so) is never touched.
# MASTER uses OpenRouter exclusively — Bedrock is never needed.
module RubyLLM
  module Providers
    module Bedrock
      module Auth
        def self.included(_base); end
      end

      def self.api_base = ""
      def self.headers(_cfg) = {}
      def self.models = []
      def self.slug = "bedrock"
    end
  end
end

```

## lib/master/builder.rb
```ruby
# frozen_string_literal: true

require_relative "builder/infra_helpers"

module Master
  module Builder
    RING_SIZE = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS = %w[exe lib/master data].freeze

    module_function

    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai_stack(root, infra)
      pipeline, gateway = build_pipeline_and_gateway(root, infra, ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    def build_infrastructure(root)
      config = Config.new(root)
      config["model"] ||= Master.default_model

      bus = EventBus.new
      ring = RingBuffer.new(RING_SIZE)
      logging = Logging.new(ring_buffer: ring, event_bus: bus)
      session = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo = Undo.new(session:, event_bus: bus, root:)
      breaker = CircuitBreakerRegistry.new(
        budget_max: config.budget_max, req_max: config.req_max, event_bus: bus
      )
      cache = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
      governor = Governor.new(config:, event_bus: bus)
      renderer = Renderer.new(config:)
      metrics = Metrics.new(root:, event_bus: bus)
      AuditLog.new(root:, event_bus: bus)

      code_index = CodeIndex.new(root:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
      mcp = McpCoordinator.new(root:, event_bus: bus)
      mcp.connect_all
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }

      memory = Memory.new(root:)
      personality = Personality.new(
        config["persona"]&.to_sym || Personality::DEFAULT, root:
      )

      phase_gates = PhaseGates.new(root:, event_bus: bus)
      {
        config:, ring:, bus:, logging:, session:, undo:, breaker:, cache:,
        governor:, renderer:, metrics:, code_index:, diff_stager:, mcp:,
        memory:, personality:, phase_gates:
      }
    end

    def build_ai_stack(root, infra)
      agent, soul_doc, scanner, swarm, deliberation, council_stage, ideation = build_agent_core(root, infra)
      autonomous = build_autonomous(root, infra, agent:, scanner:, soul: soul_doc)
      {
        agent:, soul: soul_doc, scanner:, swarm:, deliberation:, council_stage:, ideation:,
        guard: Security::InjectionGuard.new
      }.merge(autonomous)
    end

    def build_agent_core(root, infra)
      bus          = infra[:bus]
      agent, tools = build_agent_instance(root, infra)
      soul_doc     = Soul.new(root:, agent:)
      tools << Tools::AskLlm.new(agent:, governor: infra[:governor],
                                  circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus)
      ctx = ContextWindow.new(session: infra[:session], agent:, model_context: CTX_WINDOW_SIZE)
      ctx.check_and_compact!
      agent.wire_context_window(ctx)
      scanner               = build_scanner(root:, agent:, bus:)
      swarm                 = Swarm::Coordinator.new(agent:, event_bus: bus)
      deliberation, council, ideation = build_council(root, infra, agent:)
      [agent, soul_doc, scanner, swarm, deliberation, council, ideation]
    end

    def build_council(root, infra, agent:)
      personas     = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
      deliberation = Council::Deliberation.new(personas:, agent:, event_bus: infra[:bus])
      ideation     = Council::Ideation.new(agent:, event_bus: infra[:bus])
      [deliberation, Stages::Council.new(deliberation:, config: infra[:config]), ideation]
    end

    def build_agent_instance(root, infra)
      tools = build_tools(root:, infra:) + infra[:mcp].tools
      agent = Agent.new(
        config: infra[:config], session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: infra[:bus],
        model_router: Routing::ModelRouter.new(config: infra[:config]),
        reasoning_modes: Reasoning::Modes.new,
        memory: infra[:memory], personality: infra[:personality], code_index: infra[:code_index]
      )
      [agent, tools]
    end

    def build_autonomous(root, infra, agent:, scanner:, soul:)
      bus      = infra[:bus]
      standing = StandingOrders.new(pipeline: nil, event_bus: bus)
      learnings = Learnings.new(root:)
      autoloop = AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul:, learnings:)
      skills   = Skills.new(root:, event_bus: bus)
      skills.discover!
      heartbeat = Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory], event_bus: bus)
      triggers  = Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!
      { standing:, learnings:, autoloop:, skills:, heartbeat:, triggers: }
    end

    def build_pipeline_and_gateway(root, infra, ai)
      config   = infra[:config]
      bus      = infra[:bus]
      commands = CommandRegistry.build(infra:, ai:, root:)
      stages   = build_stages(root:, infra:, ai:, commands:)
      pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
      ai[:standing].wire_pipeline(pipeline)
      gateway = Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(ctx) { gateway.channels }
      [pipeline, gateway]
    end

    def build_stages(root:, infra:, ai:, commands:)
      config = infra[:config]
      bus    = infra[:bus]
      [
        Stages::Intake.new,
        Stages::Infer.new,
        Stages::Route.new(commands:, agent: ai[:agent]),
        Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Stages::Deliberate.new(agent: ai[:agent], config:),
        Stages::Execute.new,
        Pipeline::SkipOnPressure.new(Pipeline::ParallelGroup.new(
          ai[:council_stage],
          Stages::Lint.new(scanner: ai[:scanner], config:, autoloop: ai[:autoloop], root:, event_bus: bus),
          bus:
        )),
        Pipeline::SkipOnPressure.new(Stages::Prune.new),
        Stages::Memo.new(memory: infra[:memory], event_bus: bus),
        Stages::Render.new(renderer: infra[:renderer])
      ]
    end

    def build_tools(root:, infra:)
      bus = infra[:bus]
      undo = infra[:undo]
      governor = infra[:governor]
      [
        Tools::ReadFile.new(root:, undo:, event_bus: bus),
        Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::ListDir.new(root:, event_bus: bus),
        Tools::SearchFiles.new(root:, event_bus: bus),
        Tools::WebSearch.new(governor:, event_bus: bus),
        Tools::Shell.new(root:, governor:, event_bus: bus),
        Tools::BatchReplace.new(root:, governor:, event_bus: bus),
        Tools::GitContext.new(root:, event_bus: bus),
        Tools::AstEdit.new(root:, undo:, event_bus: bus),
        Tools::Tree.new(root:, event_bus: bus),
        Tools::SymbolLookup.new(code_index: infra[:code_index], event_bus: bus),
        Tools::Clean.new(root:, governor:, event_bus: bus),
        Tools::SearchKnowledge.new(root:, event_bus: bus)
      ]
    end

  end
end

```

## lib/master/circuit_breaker.rb
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  class CircuitBreaker
    include MonitorMixin

    FAILURE_THRESHOLD = 8
    COOLDOWN_S        = 30
    RATE_WINDOW_S     = 60
    RATE_MAX          = 60

    class CircuitError < StandardError
      attr_reader :category
      def initialize(msg, category) = (super(msg); @category = category)
    end

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @budget_max    = budget_max
      @bus           = event_bus
      @failures      = 0
      @opened_at     = nil
      @state         = :closed
      @session_total = 0.0
      @req_times     = []
    end

    def check_rate!
      synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @req_times.reject! { |t| now - t > RATE_WINDOW_S }
        raise CircuitError.new("rate limit: #{RATE_MAX} req/min exceeded", :infrastructure) if @req_times.size >= RATE_MAX
        @req_times << now
      end
    end

    def call(cost_estimate, &blk)
      check_budget(cost_estimate)
      check_circuit
      execute_with_tracking(blk)
    rescue CircuitError => e
      # Budget/circuit-open errors are not backend failures — don't penalize.
      Result.err(e.message, category: e.category)
    end

    def record_cost(amount)  = synchronize { @session_total += amount }
    def session_total        = synchronize { @session_total }

    def state = synchronize { @state }

    private

    def execute_with_tracking(blk)
      result = blk.call
      on_success
      result
    rescue RubyLLM::RateLimitError => e
      # API rate limit is infrastructure noise — don't open the circuit.
      Result.err("rate_limit: #{e.message}", category: :infrastructure)
    rescue StandardError => e
      on_failure
      Result.err(e.message, category: :provider_error)
    end

    def check_budget(estimate)
      return unless @budget_max.positive? # Only check budget if it's a positive value.
      synchronize do
        raise CircuitError.new("budget: $#{(@session_total + estimate).round(4)} would exceed $#{@budget_max}", :budget) if @session_total + estimate > @budget_max
      end
    end

    def check_circuit
      synchronize do
        return if @state == :closed
        if @state == :open
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
          if elapsed >= COOLDOWN_S
            @state = :half_open
          else
            raise CircuitError.new("circuit open: retry in #{(COOLDOWN_S - elapsed).ceil}s", :infrastructure)
          end
        end
      end
    end

    def on_success
      synchronize do
        @failures = 0
        if @state == :half_open
          @state = :closed
          @bus&.publish("circuit:closed", breaker: object_id)
        end
      end
    end

    def on_failure
      synchronize do
        @failures += 1
        return unless @failures >= FAILURE_THRESHOLD
        @state     = :open
        @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @bus&.publish("circuit:open", failures: @failures)
      end
    end
  end
end

```

## lib/master/circuit_breaker_registry.rb
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  # Per-model circuit breakers so a flaky free-tier endpoint doesn't affect paid fallbacks.
  class CircuitBreakerRegistry
    include MonitorMixin

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @defaults = { budget_max: budget_max, req_max: req_max, event_bus: event_bus }.freeze
      @breakers = {}
      @global   = CircuitBreaker.new(**@defaults)
    end

    def for(model_id)
      synchronize { @breakers[model_id.to_s] ||= CircuitBreaker.new(**@defaults) }
    end

    def check_rate!
      @global.check_rate!
    end

    def session_total
      synchronize { @breakers.values.sum(&:session_total) + @global.session_total }
    end

    def record_cost(amount)
      @global.record_cost(amount)
    end

    def call(cost_estimate, &blk)
      @global.call(cost_estimate, &blk)
    end

    def open_models
      synchronize do
        @breakers.filter_map { |id, breaker| id if breaker.respond_to?(:open?) && breaker.open? }
      end
    end
  end
end

```

## lib/master/cli.rb
```ruby
# frozen_string_literal: true

require_relative "cli/tts"
require_relative "cli/signals"

require "open3"
require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI
    DMESG_LINES = 50

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    attr_reader :container

    def initialize(container:)
      @container = container
      assign_container_refs!(container)
      @reader          = TTY::Reader.new(track_history: true)
      @running         = false
      @interrupt_at    = Time.now
      @last_ok         = true
      @tts_on          = Speech.available? && @config["tts"] != false
      @violations      = 0
      @scan_thread     = nil
      @seen_violations = {}
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      scan_in_background
      puts @renderer.splash(@agent.model)
      process(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      stripped = input.strip
      return if stripped.empty?

      run_input(stripped)
    end

    def run_input(input)
      return if input.strip.empty?

      accumulated = +""
      streamed = false
      thinking_shown = true

      on_chunk = chunk_accumulator(accumulated) do |text|
        if thinking_shown && $stdout.isatty
          print "\r\e[K"
          thinking_shown = false
        end
        print text
        $stdout.flush
        streamed = true
      end

      print_thinking_indicator
      result = @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      display_result(result, accumulated, streamed)
    end

    private

    def assign_container_refs!(c)
      @session     = c[:session]
      @agent       = c[:agent]
      @renderer    = c[:renderer]
      @logging     = c[:logging]
      @undo        = c[:undo]
      @config      = c[:config]
      @pipeline    = c[:pipeline]
      @scanner     = c[:scanner]
      @root        = c[:root] || Dir.pwd
      @diff_stager = c[:diff_stager]
      @bus         = c[:bus]
    end

    def repl_loop
      while @running
        tokens = @session.token_est
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations,
          tokens: tokens
        )
        line = begin
          @reader.read_line("", echo: true).chomp
        rescue StandardError => _e
          nil
        end
        break if line.nil?
        next if line.strip.empty?

        if line.strip == "/exit"
          exit_cli
        else
          run_input(line)
        end
      end
      @scan_thread&.kill
      @session.save!
    end

    def exit_cli = (@session.save!; @running = false)

    def scan_in_background
      @scan_thread = Thread.new do
        lib_dir = File.join(@root, "lib")
        changed = begin
          out, = Open3.capture2e("git", "-C", @root, "diff", "--name-only", "HEAD")
          out.strip.empty? ? [] : out.lines.map { |l| File.join(@root, l.strip) }
                                           .select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
        rescue StandardError => _e
          []
        end

        result = if changed.any?
                   Result.ok(changed.map { |p| [p, @scanner.scan(p, depth: :standard)] })
                 else
                   @scanner.scan_dir(lib_dir, depth: :standard)
                 end

        next unless result.respond_to?(:ok?) && result.ok?

        count = result.value!.sum do |_file, file_result|
          file_result.respond_to?(:ok?) && file_result.ok? ? file_result.value!.size : 0
        end
        @violations = count

        next if count.zero?

        puts "\n#{@renderer.render("boot scan: #{count} violation(s)", mode: :dim)}"
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations
        )
      rescue StandardError => e
        @bus&.publish("cli:warn", message: e.message)
      end
    end

    def chunk_accumulator(buffer)
      lambda do |chunk|
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?

        yield text
        buffer << text
      end
    end

    def print_thinking_indicator
      return unless $stdout.isatty

      print @renderer.render("thinking...", mode: :dim)
      $stdout.flush
    rescue StandardError => _e
      print "thinking..."
    end

    def display_result(result, accumulated, streamed)
      case result
      in Master::Result::Ok => ok
        @last_ok = true
        display_ok(ok, accumulated, streamed)
      in Master::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def display_ok(ok, accumulated, streamed)
      if streamed
        puts
        speak_async(accumulated) if @tts_on
      else
        print "\r\e[K" if $stdout.isatty
        value = ok.value
        text = value.is_a?(Hash) && value[:rendered] ? value[:rendered] : value.to_s
        puts text
        speak_async(text) if @tts_on
      end
    end
  end
end

```

## lib/master/code_index.rb
```ruby
# frozen_string_literal: true

require "prism"
require "set"
require "monitor"
require_relative "code_index/symbol_visitor"

module Master
  # Live Prism-parsed symbol graph; rebuilt on write events.
  class CodeIndex
    Symbol = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
    Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

    attr_reader :symbols, :references, :built_at

    def initialize(root:, event_bus: nil)
      @root = File.expand_path(root)
      @bus = event_bus
      @symbols = {}
      @references = []
      @mtimes = {}
      @built_at = nil
      @lock = Monitor.new
      @build_thread = nil
    end

    def build(path: nil)
      target = path ? File.expand_path(path, @root) : @root
      files  = Dir.glob(File.join(target, "**", "*.rb"))
                  .reject { |f| f.include?("/vendor/") }

      if @built_at.nil?
        @symbols.clear
        @references.clear
        @mtimes.clear
        files.each do |f|
          index_file(f)
          @mtimes[f] = File.mtime(f) rescue Errno::ENOENT
        end
      else
        changed = 0
        (@mtimes.keys - files).each do |gone|
          @symbols.delete_if { |_, s| s.file == gone }
          @references.reject! { |r| r.from_file == gone }
          @mtimes.delete(gone)
        end
        files.each do |f|
          mt = File.mtime(f) rescue Errno::ENOENT
          next if @mtimes[f] == mt
          reindex(f)
          @mtimes[f] = mt
          changed += 1
        end
        @bus&.publish("code_index:incremental", changed: changed, total: files.size) if changed > 0
      end

      @built_at = Time.now
      @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size)
      self
    rescue StandardError => e
      @bus&.publish("code_index:error", error: e.message)
      self
    end

    def build_async
      @build_thread = Thread.new { build }
      self
    end

    def ready?     = !@built_at.nil?
    def wait_for_build = @build_thread&.join

    def reindex(file)
      full = File.expand_path(file, @root)
      @symbols.delete_if { |_, s| s.file == full }
      @references.reject! { |r| r.from_file == full }
      index_file(full) if File.file?(full)
    rescue StandardError => e
      @bus&.publish("code_index:reindex_error", path: file, error: e.message)
    end

    def symbols_in(file)
      wait_for_build unless ready?
      full = File.expand_path(file, @root)
      @symbols.values.select { |s| s.file == full }
    end

    def find(name)
      wait_for_build unless ready?
      exact = @symbols[name]
      return [exact] if exact

      suffix = name.to_s
      @symbols.values.select { |s| s.fqn.end_with?(suffix) || s.fqn.include?(suffix) }
    end

    def references_to(fqn)
      wait_for_build unless ready?
      @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") }
    end

    def impact(fqn)
      wait_for_build unless ready?
      refs = references_to(fqn)
      files = refs.map(&:from_file).uniq.map { |f| f.sub("#{@root}/", "") }
      callers = refs.map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }.uniq
      { fqn:, reference_count: refs.size, files:, callers: }
    end

    def summary(limit: nil)
      wait_for_build unless ready?
      classes = @symbols.values
                         .select { |s| %i[class module].include?(s.type) }
                         .reject { |s| s.file.include?("/DEPLOY/") || s.file.match?(/fix_|patch_/) }
                         .reject { |s| %w[Entry Message Symbol CircuitError].any? { |n| s.fqn.end_with?("::#{n}") } }
                         .sort_by(&:fqn)
                         .map do |s|
        parent = s.parent && s.parent != "Object" ? " < #{s.parent}" : ""
        "  #{s.fqn}#{parent} (#{s.file.sub("#{@root}/", "")}:#{s.line})"
      end

      lib_count = @symbols.values.count { |s| s.file.include?("/lib/") }
      header = "# Codebase: #{lib_count} lib symbols (indexed #{built_at&.strftime("%H:%M") || "never"})"
      title = "## Classes & Modules (#{classes.size})"
      [header, title, *classes].join("\n")
    end

    def query(name)
      wait_for_build unless ready?
      hits = find(name)
      return { error: "not found: #{name}" } if hits.empty?

      hits.map do |s|
        refs = references_to(s.fqn)
        {
          fqn: s.fqn,
          type: s.type,
          file: s.file.sub("#{@root}/", ""),
          line: s.line,
          parent: s.parent,
          used_in: refs.first(10).map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }
        }
      end
    end

    def size = @symbols.size
    def built? = !@built_at.nil?

    private

    def index_file(file)
      src = File.read(file, encoding: "UTF-8")
      result = Prism.parse(src)
      return unless result.success?

      visitor = SymbolVisitor.new(file:, root: @root)
      result.value.accept(visitor)

      visitor.symbols.each { |s| @symbols[s.fqn] = s }
      @references.concat(visitor.references)
    rescue StandardError => e
      @bus&.publish("code_index:parse_error", path: file, error: e.message)
    end

  end
end

```

## lib/master/command_registry.rb
```ruby
# frozen_string_literal: true

require_relative "command_registry/agent_commands"
require_relative "command_registry/memory_commands"
require_relative "command_registry/service_commands"

module Master
  # CommandRegistry — all pipeline-routable commands in one place.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        agent_commands(ai:, root:, infra:),
        memory_commands(infra[:memory], ai[:agent]),
        service_commands(ai, infra[:phase_gates]),
        utility_commands(ai[:agent], root, infra[:cache]),
        control_commands(ai[:standing], ai[:soul]),
        "help" => ->(_ctx) {
          "just talk. intent is inferred automatically.\n" \
          "exit with /exit or ctrl-C twice."
        }
      )
    end

    def session_commands(infra)
      session = infra[:session]
      undo = infra[:undo]
      logging = infra[:logging]
      config = infra[:config]
      {
        "clear"  => ->(_ctx) { session.clear!; "context cleared" },
        "save"   => ->(_ctx) { session.save!; "session saved" },
        "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
        "undo"   => ->(_ctx) { result = undo.undo!; result.ok? ? "reverted: #{result.value!}" : result.message },
        "dmesg"  => ->(_ctx) { logging.dmesg },
        "cost"   => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "config" => ->(_ctx) { config.data.inspect }
      }
    end

    def mode_commands(config)
      reasoning_commands(config).merge(persona_commands(config)).merge(flag_commands(config))
    end

    def reasoning_commands(config)
      {
        "mode" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          Reasoning::Modes::SUPPORTED.include?(arg) ?
            (config["reasoning_mode"] = arg; config.save!; "mode: #{arg}") :
            "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
        },
        "task" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}")
        }
      }
    end

    def persona_commands(config)
      {
        "persona" => ->(ctx) {
          arg   = ctx[:args].to_s.strip.to_sym
          names = Personality::PERSONAS.keys
          if names.include?(arg)
            config["persona"] = arg.to_s; config.save!; "persona: #{arg}"
          else
            "persona: #{config["persona"] || "dark_malay"} -- available: #{names.join(", ")}"
          end
        },
      }
    end

    def flag_commands(config)
      {
        "autotest" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then config["auto_testing"] = true;  config.save!; "autotest: on"
          when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
          else "autotest: #{config.auto_testing? ? "on" : "off"}"
          end
        }
      }
    end

  end
end

```

## lib/master/config.rb
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  class Config
    BUDGET_MAX_DEFAULT = 10.0
    HISTORY_MAX = 500
    DEFAULT_WEB_PORT = 10_002

    DEFAULTS = {
      'model'          => 'nvidia/nemotron-3-super-120b-a12b:free',
      'web_host'       => '0.0.0.0',
      'web_public_url' => 'http://ai.brgen.no:3000',
      'web_port'       => DEFAULT_WEB_PORT,
      'budget_max'     => BUDGET_MAX_DEFAULT,
      'req_max'        => 1.0,
      'trace'          => 0,
      'prescan'        => true,
      'auto'           => false,
      'cache_ttl'      => 3_600,
      'history_max'    => 500,
      'reasoning_mode' => 'direct',
      'task_type'      => 'code_generation',
      'auto_testing'   => false
    }.freeze

    attr_reader :data

    def initialize(root = Dir.pwd)
      @root  = root
      @path  = File.join(root, '.master', 'config.yml')
      @mutex = Mutex.new
      @data  = load_config
    end

    def [](key)         = @data[key.to_s]
    def []=(key, value) ; @mutex.synchronize { @data[key.to_s] = value } ; end

    def model          = self['model']
    def budget_max     = self['budget_max'].to_f
    def req_max        = self['req_max'].to_f
    def trace          = (ENV['MASTER_TRACE'] || self['trace']).to_i
    def prescan?       = !!self['prescan']
    def auto?          = !!self['auto']
    def reasoning_mode = self['reasoning_mode'].to_s
    def task_type      = self['task_type'].to_s
    def auto_testing?  = !!self['auto_testing']

    # Persist atomically; fsync ensures durability.
    def save!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)

      tmp = "#{@path}.tmp.#{Process.pid}"
      File.open(tmp, 'w') do |f|
        f.write(@data.to_yaml)
        f.flush
        f.fsync
      end
      File.rename(tmp, @path)
    ensure
      File.delete(tmp) if defined?(tmp) && File.exist?(tmp) rescue nil
    end

    def reload!
      @mutex.synchronize { @data = load_config }
    end

    # Export as plain hash (deep dup to avoid external mutation)
    def to_h = Marshal.load(Marshal.dump(@data))

    private

    def load_config
      return deep_dup(DEFAULTS) unless File.exist?(@path)

      raw    = Master.load_yaml(@path)
      loaded = raw.is_a?(Hash) ? raw : {}
      deep_merge(DEFAULTS, stringify_keys(loaded))
    rescue Psych::Exception => e
      warn "config: failed to parse #{@path}: #{e.message}"
      deep_dup(DEFAULTS)
    end

    def deep_merge(a, b)
      a.merge(b) do |_key, old_val, new_val|
        old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end

    def deep_dup(hash)
      Marshal.load(Marshal.dump(hash))
    end
  end
end
```

## lib/master/context_window.rb
```ruby
# frozen_string_literal: true

module Master
  class ContextWindow
    COMPACT_THRESHOLD = 0.80
    private_constant :COMPACT_THRESHOLD

    attr_reader :session, :agent, :model_context

    def initialize(session:, agent: nil, model_context: 200_000)
      @session = session
      @agent   = agent
      @model_context = model_context
    end

    def check_and_compact!
      return Result.ok(:ok) unless agent
      return Result.ok(:ok) unless safe_to_compact?

      compact!
    end

    private

    def safe_to_compact?
      est = session.token_est
      return false unless est.is_a?(Numeric)

      est >= model_context * COMPACT_THRESHOLD
    end

    def compact!
      summary = agent.ask(
        "Summarize our progress, preserving all file paths, decisions, and remaining tasks.",
        context: session.messages
      )
      session.clear!
      session.add_message(
        role: :assistant,
        content: "[Context compacted]\n\n#{summary}"
      )
      Result.ok(:compacted)
    rescue StandardError => e
      Result.err("context compaction failed: #{e.message}", category: :infrastructure)
    end
  end
end
```

## lib/master/decision_engine.rb
```ruby
# frozen_string_literal: true

module Master
  # DecisionEngine — universal priority scorer.
  # Formula: (impact * confidence) / cost
  # Used by: ModelRouter (model selection), Heartbeat (job ordering),
  #          AutoLoop (file ordering), Swarm (worker result weighting).
  module DecisionEngine
    EPSILON = 1e-6

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    def pick_best(candidates)
      ranked(candidates).first
    end

    def ranked(candidates)
      Array(candidates).map do |c|
        c = { value: c } unless c.is_a?(Hash)
        c.merge(de_score: score(
          impact:     c.fetch(:impact,     c.fetch("impact",     1.0)),
          confidence: c.fetch(:confidence, c.fetch("confidence", 1.0)),
          cost:       c.fetch(:cost,       c.fetch("cost",       1.0))
        ))
      end.sort_by { |c| -c[:de_score] }
    end

    def converged?(previous:, current:, min_delta: 0.001)
      return false if previous.nil?
      (current.to_f - previous.to_f).abs < min_delta.to_f
    end
  end
end

```

## lib/master/diff_stager.rb
```ruby
# frozen_string_literal: true

require "diffy"
require "fileutils"
require "json"

module Master
  # DiffStager — intercepts file writes and stores diffs for human review.
  # When staging_enabled? in config, tools push here instead of writing directly.
  # CLI commands: /stage (list), /apply [n|all], /discard [n|all]
  class DiffStager
    Entry = Struct.new(:id, :path, :old_content, :new_content, :tool, :created_at, keyword_init: true) do
      def diff
        Diffy::Diff.new(old_content.to_s, new_content.to_s, context: 3)
      end

      def diff_stats
        lines  = diff.to_s.lines
        added  = lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
        removed = lines.count { |l| l.start_with?("-") && !l.start_with?("---") }
        "+#{added}/-#{removed}"
      end
    end

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @mutex   = Mutex.new
      @pending = []
      @counter = 0
    end

    # Called by tools instead of writing directly. Returns a Result.
    def stage(path:, new_content:, tool: "unknown")
      old_content = File.exist?(path) ? File.read(path) : ""
      return Result.ok("no change") if old_content == new_content

      @mutex.synchronize do
      @counter += 1
      entry = Entry.new(
        id:          @counter,
        path:        path,
        old_content: old_content,
        new_content: new_content,
        tool:        tool,
        created_at:  Time.now
      )
      @pending << entry
      end
      persist_entry(entry)
      @bus&.publish("stage:queued", id: entry.id, path: entry.path, stats: entry.diff_stats)
      Result.ok({ staged: true, id: entry.id, path: entry.path, stats: entry.diff_stats })
    end

    def pending = @pending.dup
    def empty?  = @pending.empty?
    def size    = @pending.size

    # Apply one or all entries. Returns array of applied paths.
    def apply(id: :all)
      targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
      applied = []
      targets.each do |entry|
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.new_content)
        @mutex.synchronize { @pending.delete(entry) }
        remove_persisted(entry)
        @bus&.publish("stage:applied", id: entry.id, path: entry.path)
        applied << entry.path
      end
      applied
    end

    # Discard one or all without writing.
    def discard(id: :all)
      targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
      targets.each do |entry|
        @mutex.synchronize { @pending.delete(entry) }
        remove_persisted(entry)
        @bus&.publish("stage:discarded", id: entry.id, path: entry.path)
      end
      targets.map(&:path)
    end

    # Colored summary for CLI display
    def summary(pastel)
      return pastel.dim("  (no staged changes)") if @pending.empty?
      @pending.map do |e|
        short = e.path.sub(@root + "/", "")
        "  #{pastel.yellow("[#{e.id}]")} #{pastel.white(short)} #{pastel.dim(e.diff_stats)} #{pastel.dim("via #{e.tool}")}"
      end.join("\n")
    end

    # Colored unified diff for one entry
    def render_diff(id, pastel)
      entry = @pending.find { |e| e.id == id }
      return pastel.red("no staged change with id #{id}") unless entry

      short = entry.path.sub(@root + "/", "")
      header = "#{pastel.bold(short)} #{pastel.dim(entry.diff_stats)}\n"
      diff_lines = entry.diff.to_s.lines.map do |line|
        case line[0]
        when "+" then pastel.green(line.chomp)
        when "-" then pastel.red(line.chomp)
        when "@" then pastel.cyan(line.chomp)
        else          pastel.dim(line.chomp)
        end
      end
      header + diff_lines.join("\n")
    end

    private

    def stage_dir
      File.join(@root, ".master", "pending")
    end

    def persist_entry(entry)
      FileUtils.mkdir_p(stage_dir)
      File.write(
        File.join(stage_dir, "#{entry.id}.json"),
        JSON.generate({
          id: entry.id, path: entry.path, tool: entry.tool,
          created_at: entry.created_at.iso8601,
          stats: entry.diff_stats
        })
      )
    rescue StandardError => e
      @bus&.publish("diff_stager:persist_error", error: e.message)
    end

    def remove_persisted(entry)
      persist_file = File.join(stage_dir, "#{entry.id}.json")
      # Safe to delete: this persisted staging file is being removed after the entry
      # has been either applied (written to the actual file) or discarded (abandoned).
      File.delete(persist_file) if File.exist?(persist_file)
    rescue StandardError => e
      @bus&.publish("diff_stager:cleanup_error", error: e.message)
    end
  end
end

```

## lib/master/event_bus.rb
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  class EventBus
    include MonitorMixin

    BOOT_TIME         = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    PATTERN_CACHE_MAX = 512

    def initialize
      super()
      @subscribers   = Hash.new { |h, k| h[k] = [] }
      @pattern_cache = {}
    end

    def subscribe(pattern, &handler)
      synchronize { @subscribers[pattern] << handler }
      -> { synchronize { @subscribers[pattern].delete(handler) } }
    end

    def publish(event, payload = {})
      ts      = elapsed_ms
      payload = payload.merge(event:, ts:)
      synchronize { matching_handlers(event) }.each { |h| h.call(payload) }
      self
    end

    private

    def elapsed_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - BOOT_TIME
    end

    def matching_handlers(event)
      @subscribers.flat_map { |pattern, handlers|
        handlers if glob_match?(pattern, event)
      }.compact
    end

    def glob_match?(pattern, event)
      @pattern_cache.shift if @pattern_cache.size >= PATTERN_CACHE_MAX
      re = @pattern_cache[pattern] ||= Regexp.new(
        "\\A" + Regexp.escape(pattern).gsub("\\*\\*", ".*").gsub("\\*", "[^:]*") + "\\z"
      )
      re.match?(event)
    end
  end
end

```

## lib/master/gateway.rb
```ruby
# frozen_string_literal: true

module Master
  class Gateway
    CHANNELS = %i[cli web irc matrix api].freeze

    # Contract for channel adapters.
    module Adapter
      def render(text, metadata = {})
        raise NotImplementedError, "#{self.class}#render not implemented"
      end
    end

    def initialize(pipeline:, session:, event_bus: nil)
      @pipeline = pipeline
      @session  = session
      @bus      = event_bus
      @adapters = {}
    end

    def register(channel, adapter_or_proc = nil, &block)
      handler = adapter_or_proc || block
      @adapters[channel.to_sym] = handler
    end

    def receive(channel:, message:, metadata: {})
      channel = channel.to_sym
      return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

      @bus&.publish("gateway:receive", channel: channel, size: message.bytesize)

      ctx = { user_message: message.to_s.strip, channel: channel, metadata: metadata }
      result = @pipeline.call(Result.ok(ctx))

      if (adapter = @adapters[channel])
        text = result.respond_to?(:ok?) && result.ok? ? extract_text(result) : result.to_s
        adapter.respond_to?(:render) ? adapter.render(text, metadata) : adapter.call(text, metadata)
      end

      result
    end

    def channels
      CHANNELS.map do |ch|
        status = @adapters.key?(ch) ? "active" : "available"
        "#{ch}: #{status}"
      end.join("
")
    end

    private

    def extract_text(result)
      output = result.value!
      output.is_a?(Hash) && output[:rendered] ? output[:rendered] : output.to_s
    rescue StandardError => e
      @bus&.publish("gateway:extract_error", error: e.message)
      result.to_s
    end
  end
end

```

## lib/master/git_operations.rb
```ruby
# frozen_string_literal: true

require "open3"

module Master
  # GitOperations — git wrappers scoped to a repository root.
  class GitOperations
    def initialize(root_path)
      @root_path = root_path
    end

    def dirty?(path = "lib/")
      out, = Open3.capture2e("git", "-C", @root_path, "status", "--porcelain", path)
      !out.strip.empty?
    end

    def add_lib_files
      Open3.capture2e("git", "-C", @root_path, "add", "-A", "lib/")
    end

    def commit(message)
      Open3.capture2e("git", "-C", @root_path, "commit", "-m", message.to_s)
    end
  end
end

```

## lib/master/governor.rb
```ruby
# frozen_string_literal: true

require "tty-prompt"

module Master
  class Governor
    RATE_WINDOW = 60.0
    TIERS = { safe: 0, guarded: 1, dangerous: 2 }.freeze

    # Sliding-window rate limits per tier (calls per minute).
    TIER_RATE_LIMITS = { guarded: 10, dangerous: 3 }.freeze

    def initialize(config:, event_bus: nil)
      @config        = config
      @bus           = event_bus
      @prompt        = $stdout.isatty ? TTY::Prompt.new : nil
      @auto          = config.auto?
      @approve_all   = false
      @rate_windows  = Hash.new { |h, k| h[k] = [] }
      @rate_mutex    = Mutex.new
    end

    def check_permit(tool_name, tier, description = nil)
      @bus&.publish("tool:before", tool: tool_name, tier:)

      if (rate_err = check_rate_limit!(tier))
        @bus&.publish("tool:rate_limited", tool: tool_name, tier:)
        return rate_err
      end

      case tier
      when :safe      then return Result.ok(true)
      when :guarded   then return Result.ok(true) if @auto || @approve_all
      when :dangerous then return Result.ok(true) if @auto || @approve_all
      end

      ask_user(tool_name, tier, description)
    rescue StandardError => e
      Result.err(e.message, category: :validation)
    end

    alias permit? check_permit

    def approve_all!   = @approve_all = true
    def reset_approve! = @approve_all = false

    private

    def check_rate_limit!(tier)
      limit = TIER_RATE_LIMITS[tier]
      return nil unless limit
      now = Time.now.to_f
      @rate_mutex.synchronize do
        calls = @rate_windows[tier]
        calls.reject! { |t| now - t > RATE_WINDOW }
        if calls.size >= limit
          return Result.err("rate limit: #{tier} tier (#{limit}/min)", category: :rate_limit)
        end
        calls << now
      end
      nil
    end

    def ask_user(tool_name, tier, description)
      return Result.err("non-TTY: cannot prompt for approval", category: :validation) unless @prompt

      label  = description ? "#{tool_name}: #{description}" : tool_name
      choice = @prompt.select("#{tier_icon(tier)} #{label}", [
        { name: "approve", value: :approve },
        { name: "deny",    value: :deny },
        { name: "quit",    value: :quit }
      ])

      case choice
      when :approve then Result.ok(true)
      when :deny    then @bus&.publish("tool:denied",
        tool: tool_name); Result.err("denied by user", category: :validation)
      when :quit    then exit(0)
      end
    end

    def tier_icon(tier)
      case tier
      when :safe      then "i"
      when :guarded   then "!"
      when :dangerous then "!!"
      end
    end
  end
end

```

## lib/master/heartbeat.rb
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  class Heartbeat
    POLL_INTERVAL = 60
    JOURNAL_KEEP = 50
    DATA_PATH  = File.join(Master::ROOT, "data", "heartbeat.yml").freeze
    STATE_PATH = ".master/heartbeat_state.yml".freeze

    RESULT_TRUNCATE     = 200
    SECONDS_PER_HOUR    = 3600
    SECONDS_PER_2HOURS  = 7200

    JOB_HANDLERS = {
      "prune_memory" => :prune_memory,
      "check_models" => :check_model_availability,
      "self_test"    => :run_self_test,
      "prune_undo"   => :prune_undo_journal,
      "snapshot"     => :run_snapshot
    }.freeze

    def initialize(root:, agent: nil, scanner: nil, memory: nil, event_bus: nil)
      @root    = root
      @agent   = agent
      @scanner = scanner
      @memory  = memory
      @bus     = event_bus
      @jobs    = load_jobs
      @state   = load_state
      @thread  = nil
      @stop    = false
    end

    def start!
      return if @jobs.empty?

      @stop   = false
      @thread = Thread.new do
        loop do
          break if @stop
          run_due!
          sleep POLL_INTERVAL
        end
      rescue StandardError => e
        @bus&.publish("heartbeat:error", message: e.message)
      end
    end

    def stop!
      @stop = true
      @thread&.kill
      @thread = nil
    end

    def run_due!
      now = Time.now.to_i
      results = []

      @jobs.each do |job|
        name     = job["name"]
        interval = job["interval_seconds"].to_i
        last_run = @state.dig(name, "last_run").to_i

        next unless now - last_run >= interval

        @bus&.publish("heartbeat:run", job: name)
        result = execute_job(job)
        @state[name] = { "last_run" => now, "result" => result.to_s[0, RESULT_TRUNCATE] }
        results << { name: name, result: result }
      end

      persist_state unless results.empty?
      results
    end

    def list
      @jobs.map do |job|
        last = @state.dig(job["name"], "last_run").to_i
        ago  = last.zero? ? "never" : "#{(Time.now.to_i - last) / 60}m ago"
        "#{job["name"]}: every #{job["interval_seconds"] / 60}m, last: #{ago}"
      end.join("\n")
    end

    private

    def execute_job(job)
      method_name = JOB_HANDLERS[job["action"]]
      return "unknown action: #{job["action"]}" unless method_name

      send(method_name)
    rescue StandardError => e
      "error: #{e.message}"
    end

    def prune_memory
      @memory&.consolidate!(agent: @agent) || "no memory"
    end

    def check_model_availability
      models_path = File.join(@root, "data", "models.yml")
      return "no models.yml" unless File.exist?(models_path)

      data = Master.load_yaml(models_path)
      tiers = data["models"] || {}
      ids = tiers.values.flat_map { |m| [m["id"]] }.compact
      alive = ids.select { |id| model_reachable?(id) }
      "models: #{alive.size}/#{ids.size} reachable"
    end

    def model_reachable?(model_id)
      RubyLLM.chat(model: model_id).ask("ping")
      true
    rescue StandardError => _e
      false
    end

    def run_self_test
      return "no scanner" unless @scanner

      target = File.join(@root, "lib")
      result = @scanner.scan_dir(target, depth: :standard)
      return "scan failed" unless result.respond_to?(:ok?) && result.ok?

      count = result.value!.sum do |_, fr|
        fr.respond_to?(:ok?) && fr.ok? ? fr.value!.size : 0
      end
      @bus&.publish("heartbeat:self_test", violations: count)
      "self-test: #{count} violations"
    end

    def prune_undo_journal
      journal_path = File.join(@root, ".master", "undo.jsonl")
      return "no journal" unless File.exist?(journal_path)

      lines = File.readlines(journal_path)
      return "journal empty" if lines.empty?

      keep = [lines.size / 2, JOURNAL_KEEP].max
      File.write(journal_path, lines.last(keep).join)
      "pruned undo: kept #{keep}/#{lines.size} entries"
    end

    def run_snapshot
      container = { root: @root, bus: @bus }
      Builder.boot_snapshot(container)
      "snapshot: generated"
    end

    def load_jobs
      path = File.join(@root, "data", "heartbeat.yml")
      return default_jobs unless File.exist?(path)

      result = Master.load_yaml(path); result.is_a?(Array) ? result : default_jobs
    rescue StandardError => _e
      default_jobs
    end

    def default_jobs
      [
        { "name" => "prune_memory", "action" => "prune_memory", "interval_seconds" => SECONDS_PER_HOUR },
        { "name" => "self_test", "action" => "self_test", "interval_seconds" => SECONDS_PER_2HOURS },
        { "name" => "prune_undo", "action" => "prune_undo", "interval_seconds" => 86_400 },
        { "name" => "snapshot", "action" => "snapshot", "interval_seconds" => 14_400 }
      ]
    end

    def load_state
      path = File.join(@root, STATE_PATH)
      return {} unless File.exist?(path)

      Master.load_yaml(path) || {}
    rescue StandardError => _e
      {}
    end

    def persist_state
      path = File.join(@root, STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @state.to_yaml)
    end
  end
end

```

## lib/master/learnings.rb
```ruby
# frozen_string_literal: true

require "json"

module Master
  class Learnings
    STORE_PATH = "data/learnings.jsonl".freeze
    MAX_ENTRIES = 500
    CONFIDENCE_DECAY_DAYS = 30

    def initialize(root:)
      @path    = File.join(root, STORE_PATH)
      @mutex   = Mutex.new
      @entries = load_entries
    end

    def record(trigger:, strategy:, outcome:)
      @mutex.synchronize do
        existing = @entries.find { |e| e["trigger"] == trigger.to_s && e["strategy"] == strategy.to_s }
        if existing
          existing["reuse_count"] = existing["reuse_count"].to_i + 1
          existing["confidence"]  = [existing["confidence"].to_f + 0.05, 1.0].min
          existing["outcome"]     = outcome.to_s
          existing["timestamp"]   = Time.now.to_i
        else
          @entries << {
            "trigger"     => trigger.to_s,
            "strategy"    => strategy.to_s,
            "outcome"     => outcome.to_s,
            "confidence"  => outcome == :fixed ? 0.7 : 0.4,
            "reuse_count" => 0,
            "timestamp"   => Time.now.to_i
          }
        end
        prune_old!
        persist
      end
    end

    def search(trigger_fragment, limit: 3)
      fragment = trigger_fragment.to_s.downcase
      @mutex.synchronize do
        @entries
          .select { |e| e["trigger"].to_s.downcase.include?(fragment) && e["outcome"] != "failed" }
          .sort_by { |e| -e["confidence"].to_f }
          .first(limit)
      end
    end

    def all = @mutex.synchronize { @entries.dup }

    def prune_stale!
      cutoff = Time.now.to_i - (CONFIDENCE_DECAY_DAYS * 86_400)
      @mutex.synchronize do
        before = @entries.size
        @entries.reject! { |e| e["reuse_count"].to_i == 0 && e["timestamp"].to_i < cutoff }
        persist if @entries.size < before
      end
    end

    private

    def load_entries
      return [] unless File.exist?(@path)
      File.readlines(@path, chomp: true)
          .map { |l| begin; JSON.parse(l); rescue StandardError => _e; nil; end }
          .compact
    rescue StandardError => _e
      []
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      tmp_path = "#{@path}.tmp.#{Process.pid}"
      File.write(tmp_path, @entries.map { |e| JSON.generate(e) }.join("\n") + "\n")
      File.rename(tmp_path, @path)
    end

    def prune_old!
      @entries = @entries.last(MAX_ENTRIES) if @entries.size > MAX_ENTRIES
    end
  end
end

```

## lib/master/logging.rb
```ruby
# frozen_string_literal: true

module Master
  class Logging
    DEFAULT_DMESG_LINES = 50
    attr_reader :buffer

    def initialize(ring_buffer:, event_bus:)
      @buffer      = ring_buffer
      @bus         = event_bus
      wire_events
    end

    def dmesg(lines = DEFAULT_DMESG_LINES)
      @buffer.to_a.last(lines).join("\n")
    end

    private

    def wire_events
      @bus.subscribe("**") { |payload| @buffer.push(format_entry(payload)) }
    end

    def format_entry(payload)
      event = payload[:event].to_s
      rest  = payload.except(:event, :ts)
      component, action = event.split(":", 2)
      action  ||= "ready"
      details   = rest.map { |k, v| "#{k}=#{v}" }.join(" ")
      details.empty? ? "#{component}: #{action}" : "#{component}: #{action} #{details}"
    end
  end
end

```

## lib/master/mcp_coordinator.rb
```ruby
# frozen_string_literal: true

require "ruby_llm/mcp" if $LOAD_PATH.any? { |p| File.exist?(File.join(p, "ruby_llm/mcp.rb")) }

module Master
  # McpCoordinator — manages MCP server connections and exposes
  # their tools to the agent alongside MASTER's native tools.
  # Servers are defined in data/mcp_servers.yml.
  class McpCoordinator
    CONFIG_PATH = "data/mcp_servers.yml".freeze

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @clients = {}
    end

    # Connect to all configured MCP servers. Non-fatal on failure.
    def connect_all
      servers = load_servers
      servers.each do |name, cfg|
        connect(name, cfg)
      end
      @bus&.publish("mcp:connected", count: @clients.size)
    rescue StandardError => e
      @bus&.publish("mcp:error", error: e.message)
    end

    # Return all tools from all connected MCP servers as RubyLLM::Tool wrappers.
    def tools
      @clients.flat_map do |name, client|
        client.tools.filter_map do |tool|
          McpToolWrapper.new(name:, client:, tool:)
        rescue StandardError => e
          @bus&.publish("mcp:tool_wrap_error", name:, error: e.message)
          nil
        end
      end
    rescue StandardError => e
      @bus&.publish("mcp:tools_error", error: e.message)
      []
    end

    def connected?
      @clients.any?
    end

    def server_names
      @clients.keys
    end

    private

    def connect(name, cfg)
      return unless cfg.is_a?(Hash) && cfg["enabled"] != false
      transport = (cfg["transport"] || "stdio").to_sym
      mcp_config = case transport
                   when :stdio
                     { command: cfg["command"], args: cfg["args"] || [] }
                   when :sse
                     { url: cfg["url"] }
                   else
                     return
                   end
      client = ::RubyLLM::MCP::Client.new(
        name: name,
        transport_type: transport,
        config: mcp_config,
        start: false
      )
      client.start
      @clients[name] = client
      @bus&.publish("mcp:server_connected", name:, transport: transport.to_s)
    rescue StandardError => e
      @bus&.publish("mcp:server_failed", name:, error: e.message)
    end

    def load_servers
      path = File.join(@root, CONFIG_PATH)
      return {} unless File.exist?(path)
      require "yaml"
      data = Master.load_yaml(path) || {}
      data.fetch("servers", {})
    rescue StandardError => _e
      {}
    end
  end

  # Wraps an MCP tool as a RubyLLM::Tool for the agent's tool list.
  if defined?(::RubyLLM::Tool)
    class McpToolWrapper < ::RubyLLM::Tool
      def initialize(name:, client:, tool:)
        @mcp_name   = name
        @mcp_client = client
        @mcp_tool   = tool
      end

      def name
        "#{@mcp_name}__#{@mcp_tool.name}"
      end

      def description
        "[MCP:#{@mcp_name}] #{@mcp_tool.description}"
      end

      def execute(**params)
        result = @mcp_client.call_tool(@mcp_tool.name, params)
        result.respond_to?(:content) ? result.content : result.to_s
      rescue StandardError => e
        "MCP tool error: #{e.message}"
      end
    end
  end
end

```

## lib/master/memory.rb
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

require_relative "memory/search"

module Master
  # Memory — persistent cross-session store with TF-IDF semantic search.
  # Stored at .master/memory.yml. Survives restarts.
  class Memory
    TTL_DAYS = 90
    CONSOLIDATE_THRESHOLD = 40
    SECONDS_PER_DAY = 86_400
    MAX_INJECT_TOKENS = 2000
    MAX_INJECT_ENTRIES = 5

    include Search

    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @mutex = Mutex.new
      @store = load_store
    end

    def remember(key, value)
      @mutex.synchronize do
        prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
        @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
      end
      persist
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @mutex.synchronize { @store.delete(key.to_s) }
      persist
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Token-limited injection for system prompt. Caps at MAX_INJECT_TOKENS.
    def context_summary
      active = @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
      return nil if active.empty?

      recent    = active.sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) }.first(MAX_INJECT_ENTRIES)
      lines     = []
      token_sum = 0

      recent.each do |k, v|
        text = "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}"
        est  = text.bytesize / Session::TOKENS_PER_CHAR
        break if token_sum + est > MAX_INJECT_TOKENS
        lines << text
        token_sum += est
      end
      return nil if lines.empty?

      archived_n = @store.count { |k, _| k.to_s.start_with?("archive/") }
      summary    = recall("_consolidated_summary")
      header     = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
      header    += " [+#{archived_n} archived]" if archived_n > 0
      "#{header}\n#{lines.join("\n")}"
    end

    # Three-phase consolidation: light (score), deep (archive), REM (LLM summary).
    def consolidate!(agent: nil)
      return "nothing to consolidate" if @store.empty?

      now      = Time.now.to_i
      entries  = @store.reject { |k, _| k.to_s.start_with?("archive/") }
      archived = 0

      scored = entries.map do |key, data|
        ts    = data.is_a?(Hash) ? data["ts"].to_i : 0
        value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
        age_d = (now - ts) / 86_400.0
        { key: key, value: value, score: 1.0 / (1.0 + age_d / TTL_DAYS.to_f) }
      end

      scored.each do |entry|
        next if entry[:key] == "_consolidated_summary"
        next unless entry[:score] < 0.33
        @store["archive/#{entry[:key]}"] = @store.delete(entry[:key])
        archived += 1
      end

      if agent
        active_text = @store
          .reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
          .map    { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
          .join("\n")

        unless active_text.strip.empty?
          summary = agent.ask_once(
            "Summarize in 2 concise sentences, preserving all key facts:\n#{active_text}"
          )
          remember("_consolidated_summary", summary.strip)
        end
      end

      persist
      "dreaming: #{entries.size} entries checked, #{archived} archived"
    rescue StandardError => e
      "consolidation error: #{e.message}"
    end

    private

    def prune_stale!
      cutoff = Time.now.to_i - TTL_DAYS * SECONDS_PER_DAY
      @store.each do |k, v|
        next if k.to_s.start_with?("archive/") || k == "_consolidated_summary"
        ts = v.is_a?(Hash) ? v["ts"].to_i : 0
        next unless ts > 0 && ts < cutoff
        @store["archive/#{k}"] = @store.delete(k)
      end
    end

    def load_store
      return {} unless File.exist?(@path)
      loaded = Master.load_yaml(@path, symbolize_names: false); loaded.is_a?(Hash) ? loaded : {}
    rescue StandardError => _e
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @store.to_yaml)
    end

  end
end

```

## lib/master/metrics.rb
```ruby
# frozen_string_literal: true

require "json"

module Master
  class Metrics
    SLOW_REQUEST_MS = 5000
    METRICS_PREFIX = "metrics0".freeze
    DIFF_SIZE_LIMIT_DEFAULT = 200
    MAX_DIFF_SIZE_LIMIT = DIFF_SIZE_LIMIT_DEFAULT.freeze
    MAX_DIFF_SIZE_LINES = MAX_DIFF_SIZE_LIMIT.freeze
    ROLLBACK_RATE_THRESHOLD = 0.15
    DECISION_LATENCY_MS_THRESHOLD = 5000

    def initialize(root:, event_bus: nil)
      @path        = File.join(root, ".master", "metrics.jsonl")
      @bus         = event_bus
      @mutex       = Mutex.new
      @writes      = 0
      @undos       = 0
      @latencies   = []
      @diff_sizes  = []
      @model_stats = Hash.new { |h, k| h[k] = { calls: 0, failures: 0, escalations: 0 } }
      subscribe_to_bus(event_bus) if event_bus
    end

    def record_latency(ms)
      @mutex.synchronize { @latencies << ms }
      check_threshold(:decision_latency_ms, average(@latencies))
      append(decision_latency_ms: ms)
    end

    def record_diff(lines)
      @mutex.synchronize { @diff_sizes << lines; @writes += 1 }
      check_threshold(:diff_size_lines, average(@diff_sizes))
      append(diff_size_lines: lines)
    end

    def record_undo
      rate = @mutex.synchronize { @undos += 1; @writes > 0 ? @undos.to_f / @writes : 0.0 }
      check_threshold(:rollback_rate, rate)
      append(rollback_rate: rate.round(3))
    end

    def record_llm_response(model:, success:, tokens_approx: 0, escalated: false)
      @mutex.synchronize do
        stats = @model_stats[model.to_s]
        stats[:calls]       += 1
        stats[:failures]    += 1 unless success
        stats[:escalations] += 1 if escalated
      end
      append(llm_response: { model: model.to_s, success:, tokens_approx:, escalated: })
    end

    def summary
      {
        avg_latency_ms: average(@latencies).round,
        avg_diff_lines: average(@diff_sizes).round,
        rollback_rate:  (@writes > 0 ? @undos.to_f / @writes : 0.0).round(3),
        writes:         @writes,
        undos:          @undos
      }
    end

    def model_quality
      @model_stats.transform_values do |s|
        fail_rate = s[:calls] > 0 ? (s[:failures].to_f / s[:calls]).round(3) : 0.0
        s.merge(fail_rate:)
      end.sort_by { |_, v| -v[:fail_rate] }.to_h
    end

    private

    def subscribe_to_bus(bus)
      bus.subscribe("llm:response") do |ev|
        record_llm_response(
          model:        ev[:model].to_s,
          success:      ev[:success] != false,
          tokens_approx: ev[:tokens_approx].to_i,
          escalated:    ev[:escalated] == true
        )
      rescue StandardError => e
        @bus&.publish("metrics:record_error", error: e.message)
      end
    end

    def check_threshold(metric, value)
      threshold =
        case metric
        when :decision_latency_ms then DECISION_LATENCY_MS_THRESHOLD
        when :diff_size_lines     then MAX_DIFF_SIZE_LINES
        when :rollback_rate       then ROLLBACK_RATE_THRESHOLD
        else return
        end
      return unless value > threshold
      @bus&.publish("metrics:threshold_exceeded", metric:, value:)
      warn "#{METRICS_PREFIX}: #{metric} #{value} exceeds #{threshold}"
    end

    def average(arr)
      return 0.0 if arr.empty?
      arr.sum.to_f / arr.size
    end

    def append(entry)
      entry[:ts] = Time.now.to_i
      File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
    rescue StandardError => e
      @bus&.publish("metrics:append_error", error: e.message)
    end
  end
end

```

## lib/master/personality.rb
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # MASTER's behavioral persona: voice, TTS settings, and LLM style.
  # Default: dark_malay — terse, direct, Osman TTS voice.
  class Personality
    PERSONAS = {
      dark_malay: {
        voice:       "ms-MY-OsmanNeural",
        tts_rate:    "-35%",
        tts_pitch:   "-150Hz",
        style:       :deep,
        description: "Terse. Direct. No filler. Dark."
      },
      british: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Measured. Precise. Dry wit."
      },
      norwegian: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Calm. Considered. Honest."
      },
      ronin: {
        voice:       "en-US-AndrewNeural",
        tts_rate:    "-25%",
        tts_pitch:   "-100Hz",
        style:       :deep,
        description: "Stoic. Minimal. Decisive. Says only what must be said."
      },
      lawyer: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-10%",
        tts_pitch:   "-20Hz",
        style:       :slow,
        description: "Norwegian law focus. Barnevernet, lovdata.no, sivilombudet.no. Not legal advice."
      },
      hacker: {
        voice:       "en-US-GuyNeural",
        tts_rate:    "-30%",
        tts_pitch:   "-120Hz",
        style:       :deep,
        description: "OpenBSD security. CVE analysis. Pentesting. Exploit-db."
      },
      architect: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-60Hz",
        style:       :heavy,
        description: "Parametric design. BIM. archdaily.com. dezeen.com."
      },
      sysadmin: {
        voice:       "en-AU-WilliamNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :deep,
        description: "OpenBSD. pf. httpd. vmm. man.openbsd.org."
      },
      trader: {
        voice:       "en-US-ChristopherNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Crypto. DeFi. Technicals. TradingView. CoinGecko."
      },
      medic: {
        voice:       "en-US-EricNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Medical research. PubMed. Not medical advice."
      }
    }.freeze

    DEFAULT = :dark_malay
    AXIOM_DISPLAY_LIMIT = 10

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def initialize(name = DEFAULT, root: nil)
      @name      = name.to_sym
      persona    = PERSONAS.fetch(@name, PERSONAS[DEFAULT])
      @voice     = persona[:voice]
      @tts_rate  = persona[:tts_rate]
      @tts_pitch = persona[:tts_pitch]
      @style     = persona[:style]
      @desc      = persona[:description]
      @axioms    = Axioms.new(root:)
    end

    # Injected before every LLM call. Pulls from rules.yml via Axioms.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

    def build_system_prompt
      ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
      constitution = @axioms.constitution
      strunk = @axioms.strunk
      banned  = (constitution["banned_output"] || [])
      no_open = (strunk["preambles"] || []).first(4)
      no_end  = (strunk["endings"]   || []).first(3)
      ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
      ls << "Evidence only: show diff or file content, never assert. Active voice."
      kernel = @axioms.kernel
      ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
      phil = @axioms.philosophy(limit: AXIOM_DISPLAY_LIMIT)
      ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
      golden = constitution["golden_rule"]
      ls << "Rule: #{golden}." if golden

      # Hard formatting rules — [K] enforced
      ls << "Output format: plain prose or dmesg-style lines. No markdown headers (#), no bold (**),
        no bullet lists (- *), no numbered lists. Code fences (```) are allowed only for actual code."
      ls << "Never use: Certainly, Of course, Great question, Absolutely, Happy to help, I would be glad."

      # Code generation axioms — [K] enforced
      ls << "Code axioms — refuse to generate code that violates these:"
      ls << "FAIL_VISIBLY: never rescue Exception or bare rescue that swallows errors silently. Always rescue StandardError or a specific class."
      ls << "SIMPLEST_WORKS: refuse to create god classes (>300 lines, >20 methods). Push back and suggest decomposition."
      ls << "PRESERVE_FIRST: never rewrite working code from scratch. Read first, patch minimally."
      ls << "BE_CONCISE: minimal response. If the answer is one word, say one word."

      zsh = load_yaml_data("zsh_patterns.yml")
      if zsh
        banned_cmds = Array(zsh["banned_commands"]).join(", ")
        ls << "Zsh scripts: never use #{banned_cmds}. Use pure zsh parameter expansion and builtins instead."
      end

      style = load_yaml_data("ruby_style.yml")
      if style
        bugs = Array(style.dig("ruby", "bugs_to_avoid"))
                  .map { |b| "#{b["pattern"]}: #{b["fix"] || b["note"]}" }
                  .first(5)
        ls << "Ruby bugs to avoid: #{bugs.join("; ")}." if bugs.any?
        shell_forbidden = Array(style.dig("shell", "decorations_forbidden"))
        ls << "Shell scripts: no ASCII banners (===,---), no emoji, no hardcoded credentials." if shell_forbidden.any?
      end

      ls.join("\n")
    end

    def load_zsh_patterns
      load_yaml_data("zsh_patterns.yml")
    end

    def load_yaml_data(filename)
      path = File.join(Master::ROOT, "data", filename)
      Master.load_yaml(path) if File.exist?(path)
    rescue StandardError => _e
      nil
    end
  end
end

```

## lib/master/phase_gates.rb
```ruby
# frozen_string_literal: true

module Master
  PHASES = %w[discover analyze ideate design implement validate deliver idle].freeze

  class PhaseGates
    PHASE_STATE_PATH = "data/phase_state.yml".freeze

    GATES = {
      "discover"  => %w[problem_stated success_measurable],
      "analyze"   => %w[components_distinct dependencies_noted],
      "ideate"    => %w[alternatives_gte_3],
      "design"    => %w[interfaces_noted errors_noted],
      "implement" => %w[],
      "validate"  => %w[tests_noted],
      "deliver"   => %w[deployed_noted],
      "idle"      => %w[]
    }.freeze

    def initialize(root:, event_bus: nil)
      @root  = root
      @bus   = event_bus
      @state = load_state
    end

    def current = @state["phase"] || "idle"

    def advance!(to: nil)
      prev   = current
      target = to&.to_s || next_phase
      return Master::Result.err("unknown phase: #{target}") unless PHASES.include?(target)
      return Master::Result.err("already at final phase: #{prev}") if prev == "idle" && target == "idle"

      unmet = unmet_gates(prev)
      if unmet.any?
        return Master::Result.err("phase #{prev} gates unmet: #{unmet.join(",")} — override with /phase advance --force")
      end

      @state["phase"] = target
      @state["entered_at"] = Time.now.to_i
      persist
      @bus&.publish("phase:advanced", from: prev, to: target)
      Master::Result.ok("phase: #{prev} -> #{target}")
    end

    def force!(phase)
      @state["phase"] = phase.to_s
      @state["entered_at"] = Time.now.to_i
      persist
      Master::Result.ok("phase forced to #{phase}")
    end

    def meet_gate!(gate)
      @state["met_gates"] ||= []
      @state["met_gates"] |= [gate.to_s]
      persist
    end

    def status
      unmet = unmet_gates(current)
      met   = (@state["met_gates"] || []) & (GATES[current] || [])
      "phase=#{current} met=#{met.join(",")} unmet=#{unmet.join(",")}"
    end

    private

    def next_phase
      phase_index = PHASES.index(current) || 0
      PHASES[[phase_index + 1, PHASES.size - 1].min]
    end

    def unmet_gates(phase)
      required = GATES.fetch(phase, [])
      met = @state["met_gates"] || []
      required - met
    end

    def load_state
      path = File.join(@root, PHASE_STATE_PATH)
      return { "phase" => "idle", "met_gates" => [] } unless File.exist?(path)
      data = Master.load_yaml(path)
      data.is_a?(Hash) ? data : { "phase" => "idle", "met_gates" => [] }
    rescue StandardError => _e
      { "phase" => "idle", "met_gates" => [] }
    end

    def persist
      path = File.join(@root, PHASE_STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, YAML.dump(@state))
    end
  end
end

```

## lib/master/pipeline.rb
```ruby
# frozen_string_literal: true

require "open3"

module Master
  class Pipeline
    ROLLBACK_CATEGORIES   = %i[validation axiom_violation].freeze
    MS_PER_SECOND         = 1000
    ROLLBACK_MSG_TRUNCATE = 120

    attr_reader :last_timings

    def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil)
      @stages = stages
      @last_timings = {}
      @bus   = bus || event_bus
      @trace = trace
      @root  = root
    end

    def call(initial)
      timings = {}
      @stages.reduce(initial) do |result, stage|
        result.and_then(stage_label(stage)) do |ctx|
          t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          stage_result = stage.call(ctx)
          ms     = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * MS_PER_SECOND).round
          timings[stage_label(stage)] = ms
          if stage_result.respond_to?(:ok?) && stage_result.ok?
            @last_timings = timings.dup
            @bus&.publish("pipeline:stage", stage: stage_label(stage), ms:) if @trace
            Result.ok(stage_result.value!.merge(_timings: timings.dup))
          else
            stage_result
          end
        end
      end.tap { |final| maybe_rollback(final) }
    end

    class ParallelGroup
      PARALLEL_TIMEOUT_S = 30

      def initialize(*stages, bus: nil)
        @stages = stages
        @bus    = bus
      end

      def call(ctx)
        frozen_ctx = ctx.freeze
        threads    = @stages.map do |s|
          Thread.new do
            s.call(frozen_ctx)
          rescue StandardError => e
            @bus&.publish("pipeline:stage_error", stage: s.class.name, error: e.message)
            Result.ok(frozen_ctx.merge(_stage_error: e.message))
          end
        end

        results = threads.each_with_index.map do |t, i|
          if t.join(PARALLEL_TIMEOUT_S)
            t.value
          else
            begin; t.kill; rescue ThreadError; nil; end
            @bus&.publish("pipeline:stage_timeout", stage: @stages[i].class.name)
            Result.ok(frozen_ctx.merge(_parallel_timeout: @stages[i].class.name))
          end
        end

        errors = results.filter_map { |r| r.respond_to?(:err?) && r.err? ? r.message : nil }
        merged = results.reduce(ctx) { |acc, r| r.respond_to?(:ok?) && r.ok? ? acc.merge(r.value!) : acc }
        merged = merged.merge(_parallel_errors: errors) unless errors.empty?

        Result.ok(merged)
      rescue StandardError => e
        Result.ok(ctx.merge(_parallel_errors: [e.message]))
      end
    end

    class SkipOnPressure
      def initialize(stage) = @stage = stage
      def call(ctx) = ctx[:pressure] ? Result.ok(ctx) : @stage.call(ctx)
    end

    private

    def maybe_rollback(result)
      return unless result.respond_to?(:err?) && result.err?
      return unless ROLLBACK_CATEGORIES.include?(result.category)
      return unless @root && git_workspace?
      return unless dirty?

      @bus&.publish("pipeline:rollback", category: result.category, message: result.message[0, ROLLBACK_MSG_TRUNCATE])
      Open3.capture2e("git", "-C", @root, "reset", "--hard", "HEAD")
    end

    def git_workspace?
      @root && Dir.exist?(File.join(@root, ".git"))
    end

    def dirty?
      out, _, st = Open3.capture3("git", "-C", @root, "status", "--porcelain")
      st.success? && !out.strip.empty?
    end

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end

```

## lib/master/pledge.rb
```ruby
# frozen_string_literal: true

module Master
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      require "fiddle"
      require "fiddle/import"

      module LibC
        extend Fiddle::Importer
        dlload "libc.so"
        extern "int pledge(const char *, const char *)"
        extern "int unveil(const char *, const char *)"
      end

      def pledge(promises, execpromises = nil)
        result = LibC.pledge(promises, execpromises || Fiddle::NULL)
        raise SystemCallError.new("pledge failed", Fiddle.last_error) if result == -1
      end

      def unveil(path, permissions)
        result = LibC.unveil(path, permissions)
        raise SystemCallError.new("unveil failed", Fiddle.last_error) if result == -1
      end

      def lock_unveil! = LibC.unveil(Fiddle::NULL, Fiddle::NULL)
    else
      def pledge(*) = nil
      def unveil(*) = nil
      def lock_unveil! = nil
    end

    # Stage 1: called before Builder.build -- widest promises, no lock
    # "error" converts unknown-ioctl pledge kills to EPERM so tty gems degrade gracefully.
    def stage1_boot!(root)
      pledge("stdio rpath wpath cpath proc exec inet dns tty unveil prot_exec error")
      unveil("/", "")
      unveil(root, "rwc")
      unveil(Dir.home, "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      unveil("/usr/local/lib", "r")
      unveil("/usr/local/share", "r")
      [Dir.home + "/.local/share/gem", Dir.home + "/.gem"].each { |p| unveil(p, "r") if Dir.exist?(p) }
      unveil("/dev/urandom", "r")
    end

    # Stage 2: called after CLI is fully initialized -- lock filesystem
    def stage2_lock!
      lock_unveil!
      pledge("stdio rpath wpath cpath proc exec inet dns tty prot_exec error")
    end

    # Stage 3: scan-only sessions (no network, no exec)
    def stage3_scan_only!
      lock_unveil!
      pledge("stdio rpath wpath cpath tty")
    end

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
  end
end

```

## lib/master/reflexion.rb
```ruby
# frozen_string_literal: true

module Master
  module Reflexion
    MAX_REFLECTIONS   = 3
    TASK_TRUNCATE     = 400
    HISTORY_TRUNCATE  = 200

    module_function

    def run(agent:, task:, fast_model: nil, max: MAX_REFLECTIONS)
      last_result = nil
      last_critique = nil

      (max + 1).times do |i|
        prompt = i.zero? ? task : build_revision_prompt(task, last_result, last_critique)
        last_result = yield(prompt, i)
        return last_result if last_result.respond_to?(:ok?) && last_result.ok?

        break if i >= max
        last_critique = critique(agent:, task:, result: last_result, fast_model:)
      end

      last_result
    end

    def critique(agent:, task:, result:, fast_model: nil)
      prompt = <<~PROMPT
        Task: #{task.to_s[0, TASK_TRUNCATE]}
        Attempt output: #{result.to_s[0, TASK_TRUNCATE]}
        What specifically went wrong? Name the constraint violated. What must change in the next attempt? One paragraph, no preamble.
      PROMPT
      resp = fast_model ? agent.ask_once(prompt, model: fast_model) : agent.ask(prompt)
      resp.respond_to?(:value!) ? resp.value! : resp.to_s
    rescue StandardError => _e
      "previous attempt failed — try a different approach"
    end

    def build_revision_prompt(task, previous_result, critique)
      <<~PROMPT
        #{task}

        Previous attempt failed.
        Critique: #{critique}
        Previous output: #{previous_result.to_s[0, HISTORY_TRUNCATE]}

        Revise based on the critique. Return only the corrected result.
      PROMPT
    end
  end
end

```

## lib/master/renderer.rb
```ruby
# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"
require "socket"

module Master
  DEFAULT_WEB_PORT = Config::DEFAULT_WEB_PORT

  class Renderer
    TICK  = "\u2714".freeze
    CROSS = "\u2718".freeze
    DMESG_LINE_COUNT = 5
    MILLISECONDS_PER_SECOND = 1000

    def initialize(config:)
      @config = config
      @p      = Pastel.new
    end

    def splash(model)
      now   = Time.now
      host  = Socket.gethostname rescue "openbsd"
      ruby  = RUBY_VERSION
      up    = uptime_str
      url   = @config["web_public_url"] || "https://ai.brgen.no"
      mod   = short_model(model)
      rev   = git_rev

      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << @p.bold.red("MASTER") + @p.dim(" constitutional AI agent")
      lines << @p.dim("hostname #{host}  ruby #{ruby}  #{now.strftime('%Y-%m-%d %H:%M:%S')}")
      lines << @p.dim("model    #{mod}")
      lines << @p.dim("web      #{url}")
      lines << @p.dim("rev      #{rev}") if rev
      lines << @p.dim("uptime   #{up}") if up
      lines << ""
      lines << @p.bold.red("master") + @p.dim("@#{host} ready -- type ") + @p.bright_red("help") + @p.dim(" for commands")
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil)
      branch = git_branch
      tok    = tokens && tokens > 0 ? @p.dim("#{tokens}t ") : ""
      vbadge = violations > 0 ? @p.red("[#{violations}v] ") : ""
      branch_str = branch ? "#{@p.dim("(")}#{@p.red(branch)}#{@p.dim(")")} " : ""
      dollar = last_ok ? @p.bright_red("$") : @p.red("$")
      "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{branch_str}#{tok}#{vbadge}#{dollar} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.bright_red(TICK)} #{@p.bright_red(content)}"
      when :warning then @p.red("! #{content}")
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then format_dmesg(content)
      else               content.to_s
      end
    end

    def format_error(message)
      render(message, mode: :error)
    end

    def format_dmesg(line)
      @p.dim(line.to_s)
    end

    private

    def uptime_str
      out, = Open3.capture2e("uptime")
      out = out.strip
      out.empty? ? nil : out.split(",").first.gsub(/.*up\s+/, "").strip
    rescue StandardError => _e
      nil
    end

    def git_rev
      out, _, st = Open3.capture3("git", "-C", @config["root"] || Dir.pwd, "rev-parse", "--short", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError => _e
      nil
    end

    def short_model(model)
      model.to_s.split("/").last
    end

    def git_branch
      out, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      status.success? ? out.strip : nil
    rescue StandardError => _e
      nil
    end

    def dmesg_lines
      stdout, _stderr, _status = Open3.capture3("dmesg")
      raw = stdout.lines.first(DMESG_LINE_COUNT).map(&:chomp)
      raw.empty? ? ["dmesg unavailable"] : raw
    rescue StandardError => _e
      ["dmesg unavailable"]
    end

    def elapsed_ms
      @start_ms ||= (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MILLISECONDS_PER_SECOND).to_i
      now = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MILLISECONDS_PER_SECOND).to_i
      format("%d.%03d", (now - @start_ms) / MILLISECONDS_PER_SECOND, (now - @start_ms) % MILLISECONDS_PER_SECOND)
    end
  end
end
```

## lib/master/result.rb
```ruby
# frozen_string_literal: true

module Master
  class Result
    def self.ok(value)                      = Ok.new(value)
    def self.err(msg, category: :unknown)   = Err.new(msg, category)
    def self.wrap(val)                      = val.respond_to?(:ok?) ? val : Ok.new(val)

    class Ok
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def ok?              = true
      def err?             = false
      def value!           = @value
      def unwrap           = @value
      def value_or(_)      = @value

      def map(&blk)        = Result.ok(blk.call(@value))
      def flat_map(&blk)   = blk.call(@value)

      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.respond_to?(:ok?) ? result : Result.ok(result)
      rescue StandardError => e
        Result.err("#{label || "stage"}: #{e.message}", category: :unknown)
      end

      def deconstruct_keys(_keys) = { value: @value }
      def to_s                    = @value.to_s
      def inspect                 = "Ok(#{@value.inspect})"
    end

    class Err
      attr_reader :message, :category

      RETRIABLE = %i[infrastructure timeout].freeze
      PERMANENT = %i[validation axiom_violation budget].freeze

      def initialize(message, category = :unknown)
        @message  = message
        @category = category
        freeze
      end

      def ok?                   = false
      def err?                  = true
      def value!                = raise(Master::UnwrapError, "Err#value\! called: #{@message}")
      def unwrap                = value!
      def value_or(default)     = default

      def map(&)                = self
      def flat_map(&)           = self
      def and_then(*)           = self

      def retriable?            = RETRIABLE.include?(@category)
      def permanent?            = PERMANENT.include?(@category)

      def deconstruct_keys(_keys) = { message: @message, category: @category }
      def to_s                    = @message
      def inspect                 = "Err(#{@category}: #{@message})"
    end
  end
end

```

## lib/master/ring_buffer.rb
```ruby
# frozen_string_literal: true

module Master
  class RingBuffer
    include Enumerable
    include MonitorMixin

    def initialize(capacity)
      super()
      @capacity = capacity
      @buffer      = Array.new(capacity)
      @start    = 0
      @size     = 0
    end

    def push(item)
      synchronize do
        write_pos = (@start + @size) % @capacity
        if @size < @capacity
          @buffer[write_pos] = item
          @size += 1
        else
          @buffer[@start] = item
          @start = (@start + 1) % @capacity
        end
      end
      self
    end

    alias << push

    def each
      return enum_for(__method__) unless block_given?
      synchronize { @size.times { |i| yield @buffer[(@start + i) % @capacity] } }
    end

    def to_a    = @size.times.map { |i| @buffer[(@start + i) % @capacity] }
    def size    = @size
    def full?   = @size == @capacity
    def empty?  = @size.zero?

    def clear
      @start = @size = 0
      self
    end
  end
end

```

## lib/master/ruby_llm_patch.rb
```ruby
# frozen_string_literal: true

module RubyLLM
  DEFAULT_MAX_TOKENS = 4096

  class Models
    class << self
      def read_from_json(file = RubyLLM.config.model_registry_file)
        data = File.exist?(file) ? File.read(file, encoding: "utf-8") : "[]"
        JSON.parse(data, symbolize_names: true).map { |model| Model::Info.new(model) }
      rescue JSON::ParserError
        []
      end
    end

    private

    def find_without_provider(model_id)
      exact_matches = all.select { |m| m.id == model_id }
      return preferred_match(exact_matches) if exact_matches.any?

      resolved_id = Aliases.resolve(model_id)
      alias_matches = all.select { |m| m.id == resolved_id }
      return preferred_match(alias_matches) if alias_matches.any?

      Model::Info.new({
        id: model_id.to_s,
        name: model_id.to_s,
        provider: "openrouter",
        type: "chat",
        family: model_id.to_s.split("/").first,
        context_window: 128_000,
        max_tokens: DEFAULT_MAX_TOKENS,
        input_price_per_million: 0.0,
        output_price_per_million: 0.0,
        modalities: { input: ["text"], output: ["text"] },
        metadata: {}
      })
    end
  end
end

```

## lib/master/semantic_cache.rb
```ruby
# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  class SemanticCache
    MAX_ENTRIES = 1000
    DEFAULT_TTL = 3600
    BYTES_PER_KB = 1024.0

    def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
      @root = File.join(root, ".master", "cache")
      @ttl  = ttl
      @bus  = event_bus
      @lru  = []
      @lock = Monitor.new
      Dir.mkdir(@root) unless Dir.exist?(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      @lock.synchronize do
        hit = read_entry(path)
        if hit
          @bus&.publish("cache:hit", key:)
          return hit
        end
      end

      @bus&.publish("cache:miss", key:)
      result = blk.call
      @lock.synchronize { write_entry(path, result, key) }
      result
    end

    def invalidate!(prompt, model)
      path = cache_path(cache_key(prompt, model))
      @lock.synchronize { File.delete(path) if File.exist?(path) }
    end

    def invalidate_all!
      @lock.synchronize do
        Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue Errno::ENOENT }
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum { |f| File.exist?(f) ? File.size(f) : 0 }
        { entries: files.size, size_kb: (bytes / BYTES_PER_KB).round(1) }
      end
    end

    private

    def cache_key(prompt, model) = Digest::SHA256.hexdigest("#{prompt}::#{model}")
    def cache_path(key) = File.join(@root, "#{key}.json")

    def stale?(entry) = Time.now.to_i - entry[:ts] > @ttl

    def expire_entry!(path)
      @lru.delete(path)
      File.delete(path) rescue Errno::ENOENT
      nil
    end

    def drop_entry!(path)
      File.delete(path) rescue Errno::ENOENT
      @lru.delete(path)
      nil
    end

    def read_entry(path)
      return nil unless File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      return expire_entry!(path) if stale?(entry)
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError
      drop_entry!(path)
    end

    def write_entry(path, value, key)
      value = value.value! if value.respond_to?(:ok?) && value.ok?
      evict_lru while @lru.size >= MAX_ENTRIES
      File.write(path, JSON.generate({ ts: Time.now.to_i, value: }))
      @lru.push(path)
    end

    def promote_lru(path)
      @lru.delete(path)
      @lru.push(path)
    end

    def evict_lru
      oldest = @lru.shift
      return unless oldest && File.exist?(oldest)
      File.delete(oldest) rescue Errno::ENOENT
    end
  end
end

```

## lib/master/session.rb
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  class Session
    TOKENS_PER_CHAR  = 4
    SESSION_NAME_MAX = 40
    COSTS_MAX_BYTES  = 102_400     # 100 KB

    attr_reader :name, :messages, :cost, :phase, :snapshots

    def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
      @root       = root
      @budget_max = budget_max
      @req_max    = req_max
      @mutex      = Mutex.new
      @messages   = []
      @snapshots  = {}
      @cost       = 0.0
      @phase      = :discover
      @name       = nil
      @path       = File.join(root, ".master", "session.json")
      @costs_path = File.join(root, ".master", "costs.jsonl")
      Dir.mkdir(File.join(root, ".master")) unless Dir.exist?(File.join(root, ".master"))
    end

    def add_message(role:, content:)
      msg = { role:, content:, ts: Time.now.to_i }
      @mutex.synchronize do
        @messages << msg
        @name ||= auto_name(content) if role == :user
      end
      msg
    end

    def record_cost(amount, model:, tokens:)
      entry = nil
      @mutex.synchronize do
        @cost += amount
        entry = { ts: Time.now.to_i, amount:, model:, tokens:, total: @cost }
      end
      rotate_costs! if File.exist?(@costs_path) && File.size(@costs_path) > COSTS_MAX_BYTES
      File.open(@costs_path, "a") { |f| f.puts(JSON.generate(entry)) }
      entry
    end

    def snapshot(path, content)
      @snapshots[path] ||= []
      @snapshots[path] << content
    end

    def last_snapshot(path)
      @snapshots[path]&.last
    end

    def save!
      FileUtils.mkdir_p(File.dirname(@path))
      data = { name: @name, phase: @phase, messages: @messages, cost: @cost, ts: Time.now.to_i }
      File.write(@path, JSON.generate(data))
    end

    def load!
      return self unless File.exist?(@path)
      begin
        data = JSON.parse(File.read(@path), symbolize_names: true)
      rescue JSON::ParserError, Errno::ENOENT
        data = {}
      end
      @name     = data[:name]
      @phase    = data[:phase]&.to_sym || :discover
      @messages = data[:messages] || []
      @cost     = data[:cost].to_f
      self
    end

    def exists?    = File.exist?(@path)
    def clear!     = (@messages = [] ; @cost = 0.0 ; @name = nil ; self)
    def token_est  = @messages.sum { |m| m[:content].to_s.bytesize / TOKENS_PER_CHAR }

    private

    def auto_name(content)
      content.to_s.split.first(5).join(" ").then { |s| s[0, SESSION_NAME_MAX] }
    end

    def rotate_costs!
      return unless File.exist?(@costs_path)

      lines = File.readlines(@costs_path)
      # Keep the most recent half of the lines
      keep  = lines.last([lines.size / 2, 1].max)
      File.write(@costs_path, keep.join)
    end
  end
end

```

## lib/master/skills.rb
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # Skills — discovers and loads composable skill directories.
  # Each skill is a directory under skills/ containing:
  #   SKILL.md   — metadata (name, description, trigger patterns)
  #   skill.rb   — optional Ruby implementation (loaded as a tool)
  #
  # Skills discovered at boot are available via /skills; tool registration is pending.
  class Skills
    SKILLS_DIR = "skills".freeze

    attr_reader :loaded

    def initialize(root:, event_bus: nil)
      @root   = root
      @bus    = event_bus
      @loaded = []
    end

    def discover!
      skills_path = File.join(@root, SKILLS_DIR)
      return [] unless Dir.exist?(skills_path)

      Dir.children(skills_path).sort.each do |name|
        dir = File.join(skills_path, name)
        next unless File.directory?(dir)

        skill = load_skill(dir, name)
        @loaded << skill if skill
      end

      @bus&.publish("skills:loaded", count: @loaded.size)
      @loaded
    end

    def list
      return "(no skills loaded)" if @loaded.empty?

      @loaded.map { |s| "#{s[:name]}: #{s[:description]}" }.join("\n")
    end

    def find(name)
      @loaded.find { |s| s[:name] == name.to_s }
    end

    def trigger_for(input)
      @loaded.select do |s|
        s[:triggers]&.any? { |t| input.match?(Regexp.new(t, Regexp::IGNORECASE)) }
      end
    end

    private

    def load_skill(dir, name)
      md_path = File.join(dir, "SKILL.md")
      rb_path = File.join(dir, "skill.rb")

      metadata = parse_skill_md(md_path) if File.exist?(md_path)
      metadata ||= { "name" => name, "description" => name }

      skill = {
        name:        metadata["name"] || name,
        description: metadata["description"] || name,
        triggers:    metadata["triggers"] || [],
        dir:         dir,
        has_ruby:    File.exist?(rb_path)
      }

      if File.exist?(rb_path)
        begin
          require rb_path
          @bus&.publish("skills:ruby_loaded", skill: name)
        rescue StandardError => e
          @bus&.publish("skills:load_error", skill: name, error: e.message)
        end
      end

      skill
    rescue StandardError => e
      @bus&.publish("skills:load_error", skill: name, error: e.message)
      nil
    end

    def parse_skill_md(path)
      content = File.read(path, encoding: "UTF-8")
      return {} unless content.start_with?("---")

      parts = content.split("---", 3)
      return {} if parts.size < 3

      YAML.safe_load(parts[1]) || {}
    rescue StandardError => _e
      {}
    end
  end
end

```

## lib/master/soul.rb
```ruby
# frozen_string_literal: true

require "open3"
require "yaml"
require "fileutils"

module Master
  # Manages SOUL.md identity document; Evolution Protocol: propose→test→approve→tag.
  class Soul
    SOUL_PATH     = File.join(Master::ROOT, "SOUL.md").freeze
    PROPOSAL_PATH = File.join(Master::ROOT, ".master", "soul_proposal.md").freeze

    # Drift boundaries — changes to ABSOLUTE sections are blocked without override.
    ABSOLUTE_PATTERNS  = [/anti-simulation rule/i, /golden rule/i, /preserve.*then.*improve/i].freeze
    PROTECTED_PATTERNS = [/voice character/i, /terse.*direct.*dark/i].freeze

    def initialize(root: Master::ROOT, agent: nil)
      @root  = root
      @agent = agent
      @soul  = load_soul
    end

    # Wire the agent after construction (avoids circular dependency in build).
    def wire_agent(agent) = @agent = agent

    def summary
      version = extract_version
      persona = extract_field("Persona")
      voice   = extract_field("Voice").to_s.lines.first.to_s.strip[0, 120]
      "SOUL.md v#{version} | persona: #{persona}\n#{voice}"
    end

    def changelog
      block = @soul[/## Changelog\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      block.empty? ? "(no changelog)" : block
    end

    def propose(rationale, agent: @agent)
      return "no agent available for drafting" unless agent

      current = @soul
      prompt  = <<~PROMPT
        You are editing SOUL.md — a constitutional identity document for an AI coding agent.
        Current document:
        #{current}

        Proposed change rationale: #{rationale}

        Draft ONLY the minimal changes needed. Preserve the anti-simulation rule,
          golden rule, and voice character unchanged.
        Output the full updated SOUL.md. No preamble.
      PROMPT

      draft = agent.ask_once(prompt)
      return "draft failed" if draft.to_s.strip.empty?

      drift = measure_drift(current, draft)
      blocked = drift[:absolute_changed].any?

      if blocked
        "BLOCKED: proposal would change ABSOLUTE sections: #{drift[:absolute_changed].join(", ")}. Add /override to force."
      else
        FileUtils.mkdir_p(File.dirname(PROPOSAL_PATH))
        tmp_w = "#{PROPOSAL_PATH}.tmp.#{Process.pid}"
        File.write(tmp_w, draft)
        File.rename(tmp_w, PROPOSAL_PATH)
        risk = drift[:protected_changed].any? ? " [PROTECTED sections affected: #{drift[:protected_changed].join(", ")}]" : ""
        "proposal saved#{risk}. Review with `soul diff`, approve with `soul approve`, reject with `soul reject`."
      end
    rescue StandardError => e
      "proposal error: #{e.message}"
    end

    def diff
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)
      lines_old = @soul.lines
      lines_new = proposal.lines
      changes = lines_new.reject { |l| lines_old.include?(l) }
      removals = lines_old.reject { |l| lines_new.include?(l) }
      out = []
      out += removals.first(10).map { |l| "- #{l.chomp}" }
      out += changes.first(10).map { |l| "+ #{l.chomp}" }
      out.empty? ? "(no visible changes)" : out.join("\n")
    end

    def approve
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)

      old_version = extract_version
      new_version = bump_version(old_version, :patch)

      # Inject new version into proposal
      updated = proposal.sub(/Version: [\d.]+/, "Version: #{new_version}")
      # Update changelog entry
      date    = Time.now.strftime("%Y-%m-%d")
      entry   = "| #{new_version} | #{date} | Evolution Protocol change | Approved via `soul approve` |\n"
      updated = updated.sub(/\| 1\.0\.0 \|/, entry + "| 1.0.0 |")

      tmp_w = "#{SOUL_PATH}.tmp.#{Process.pid}"
      File.write(tmp_w, updated)
      File.rename(tmp_w, SOUL_PATH)
      File.unlink(PROPOSAL_PATH)
      @soul = updated

      # Git tag
      Open3.capture2e("git", "-C", @root, "add", "SOUL.md")
      Open3.capture2e("git", "-C", @root, "commit", "-m", "soul: v#{new_version} — evolution protocol update")

      "soul updated to v#{new_version}"
    rescue StandardError => e
      "approve error: #{e.message}"
    end

    def reject
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      File.unlink(PROPOSAL_PATH)
      "proposal rejected"
    end

    def rollback
      log_out, = Open3.capture2e("git", "-C", @root, "log", "--oneline", "SOUL.md")
      out = log_out.lines
      return "no git history for SOUL.md" if out.size < 2
      prev_sha = out[1].split.first
      restored, = Open3.capture2e("git", "-C", @root, "show", "#{prev_sha}:SOUL.md")
      tmp_w = "#{SOUL_PATH}.tmp.#{Process.pid}"
      File.write(tmp_w, restored)
      File.rename(tmp_w, SOUL_PATH)
      @soul = restored
      "rolled back to #{prev_sha} — #{out[1].chomp}"
    rescue StandardError => e
      "rollback error: #{e.message}"
    end

    def system_prompt
      voice  = @soul[/## Voice\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      values = @soul[/## Values\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      "#{voice}\n\n#{values}"
    end

    def propose_from_violations(rule_id, sample_violations, agent: @agent)
      return "no agent available" unless agent

      examples  = sample_violations.first(3).map { |v| "  L#{v[:line]}: #{v[:message]}" }.join("\n")
      rationale = "Recurring scan rule '#{rule_id}' flagged #{sample_violations.size} " \
                  "violations across multiple files and cycles:\n#{examples}\n" \
                  "Propose whether the codebase axioms or soul principles should acknowledge this pattern " \
                  "or whether the rule needs refinement."
      propose(rationale, agent:)
    end

    private

    def load_soul
      File.exist?(SOUL_PATH) ? File.read(SOUL_PATH, encoding: "UTF-8") : ""
    rescue StandardError => _e
      ""
    end

    def extract_version
      @soul[/^Version: ([\d.]+)/, 1] || "1.0.0"
    end

    def extract_field(name)
      @soul[/^#{Regexp.escape(name)}:\s*(.+)/, 1].to_s.strip
    end

    def bump_version(ver, level)
      parts = ver.split(".").map(&:to_i)
      case level
      when :major then "#{parts[0] + 1}.0.0"
      when :minor then "#{parts[0]}.#{parts[1] + 1}.0"
      when :patch then "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
      end
    end

    def measure_drift(old_doc, new_doc)
      absolute_changed  = ABSOLUTE_PATTERNS.select  { |p| old_doc.match?(p) && !new_doc.match?(p) }.map(&:source)
      protected_changed = PROTECTED_PATTERNS.select { |p| old_doc.match?(p) && !new_doc.match?(p) }.map(&:source)
      { absolute_changed:, protected_changed: }
    end
  end
end

```

## lib/master/speech.rb
```ruby
# frozen_string_literal: true

require "securerandom"
require "fileutils"

module Master
  module Speech
    EDGE_TTS = %w[/home/dev/.local/bin/edge-tts /usr/local/bin/edge-tts].find { |p| File.executable?(p) }
    ESPEAK   = %w[/usr/bin/espeak /usr/local/bin/espeak].find { |p| File.executable?(p) }

    VOICES = {
      osman:   "ms-MY-OsmanNeural",
      yasmin:  "en-MY-YasminNeural",
      ryan:    "en-GB-RyanNeural",
      finn:    "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
    }.freeze

    STYLES = {
      deep:    { rate: "-35%", pitch: "-150Hz" },
      heavy:   { rate: "-30%", pitch: "-120Hz" },
      normal:  { rate: "+0%",  pitch: "+0Hz"   },
      slow:    { rate: "-20%", pitch: "-60Hz"  },
      natural: { rate: "+8%",  pitch: "+20Hz"  }
    }.freeze

    DEFAULT_VOICE = :osman
    DEFAULT_STYLE = :natural

    PULSE_SOCKET     = "/tmp/pulse/native".freeze
    PULSE_DAEMON     = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze
    PAPLAY_CANDIDATES = %w[
      /data/data/com.termux/files/usr/bin/paplay
      /usr/bin/paplay
      /usr/local/bin/paplay
    ].freeze
    FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze
    DIRECT_PLAYERS    = %w[aucat mpv ffplay aplay].freeze

    module_function

    def available?
      !EDGE_TTS.nil? || !ESPEAK.nil?
    end

    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      return nil if text.to_s.strip.empty?

      if EDGE_TTS
        synthesize_edge(text, voice: voice, style: style)
      elsif ESPEAK
        synthesize_espeak(text)
      end
    end

    def synthesize_bytes(text, **opts)
      path = synthesize(text, **opts)
      return nil unless path
      bytes = File.binread(path)
      File.unlink(path) rescue StandardError => _e
      bytes
    end

    def play(audio_path)
      return false unless audio_path && File.exist?(audio_path)
      play_via_pulse(audio_path) || play_direct(audio_path)
    end

    private

    module_function

    def synthesize_edge(text, voice:, style:)
      audio_path   = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
      voice_name   = VOICES.fetch(voice.to_sym, VOICES[DEFAULT_VOICE])
      style_config = STYLES.fetch(style.to_sym, STYLES[DEFAULT_STYLE])

      ok = system(
        EDGE_TTS,
        "--voice", voice_name,
        "--rate=#{style_config[:rate]}",
        "--pitch=#{style_config[:pitch]}",
        "--text", text.to_s,
        "--write-media", audio_path,
        out: File::NULL, err: File::NULL
      )

      (ok && File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end

    def synthesize_espeak(text)
      audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
      ok         = system(
        ESPEAK, "-s", "140", "-p", "30", "-a", "150",
        "-w", audio_path, text.to_s,
        out: File::NULL, err: File::NULL
      )
      (ok && File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end
  end
end

```

## lib/master/standing_orders.rb
```ruby
# frozen_string_literal: true

module Master
  class StandingOrders
    DAILY_INTERVAL   = 86_400
    WEEKLY_INTERVAL  = 604_800
    ERROR_TRUNCATE   = 200
    STORE_PATH       = File.join(Master::ROOT, "data", "standing_orders.yml")
    VALID_STATES    = %w[pending running done error].freeze

    BUILTIN_ORDERS = [
      { name: "nightly_dreams", description: "Consolidate memories during low-activity periods",
        trigger: "scheduled", interval_s: 86_400, command: "dreams consolidate", enabled: true },
      { name: "weekly_scan", description: "Weekly codebase axiom scan for regressions",
        trigger: "scheduled", interval_s: 604_800, command: "scan", enabled: false }
    ].freeze

    def initialize(pipeline: nil, event_bus: nil)
      @pipeline = pipeline
      @bus      = event_bus
      @orders   = load_orders
    end

    def wire_pipeline(pipeline)
      @pipeline = pipeline
    end

    def due
      now = Time.now.to_i
      @orders.select do |o|
        o["enabled"] &&
          o["trigger"] == "scheduled" &&
          %w[pending done].include?(state_of(o)) &&
          (now - o["last_run_at"].to_i) >= o["interval_s"].to_i
      end
    end

    def run_due!
      results = []
      due.each do |order|
        order["state"] = "running"
        persist

        result = execute_order(order)
        order["last_run_at"] = Time.now.to_i

        if result.ok?
          order["state"] = "done"
          order.delete("last_error")
        else
          order["state"] = "error"
          order["last_error"] = result.message.to_s[0, ERROR_TRUNCATE]
        end

        results << { name: order["name"], result: }
        @bus&.publish("standing_order:ran", name: order["name"], ok: result.ok?, state: order["state"])
      end
      persist if results.any?
      results
    end

    def upsert(name:, description: "", trigger: "scheduled",
               interval_s: 86_400, command:, enabled: true)
      existing = @orders.find { |o| o["name"] == name.to_s }
      if existing
        existing.merge!(
          "description" => description, "trigger" => trigger.to_s,
          "interval_s"  => interval_s.to_i, "command" => command.to_s, "enabled" => enabled
        )
      else
        @orders << {
          "name" => name.to_s, "description" => description.to_s, "trigger" => trigger.to_s,
          "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled,
          "state" => "pending", "last_run_at" => 0
        }
      end
      persist
      "standing order '#{name}' saved"
    end

    def enable(name)  = toggle(name, true)
    def disable(name) = toggle(name, false)

    def reset(name)
      order = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless order
      order["state"] = "pending"
      order.delete("last_error")
      persist
      "'#{name}' reset -> pending"
    end

    def list
      return "no standing orders defined" if @orders.empty?
      @orders.map do |o|
        st   = state_of(o)
        flag = o["enabled"] ? "on" : "off"
        last = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
        err  = o["last_error"] ? "  !! #{o["last_error"][0, 60]}" : ""
        "#{o['name']} [#{flag}|#{st}] - #{o['description']} (last: #{last})#{err}"
      end.join("\n")
    end

    private

    def state_of(order) = VALID_STATES.include?(order["state"]) ? order["state"] : "done"

    def execute_order(order)
      return Result.err("no pipeline") unless @pipeline
      @pipeline.call(Result.ok(user_message: order["command"].to_s))
    rescue StandardError => e
      Result.err(e.message)
    end

    def toggle(name, enabled)
      order = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless order
      order["enabled"] = enabled
      persist
      "#{name} #{enabled ? 'enabled' : 'disabled'}"
    end

    def load_orders
      if File.exist?(STORE_PATH)
        orders = Master.load_yaml(STORE_PATH)
        unless orders.is_a?(Array)
          @bus&.publish("standing_orders:corrupt", path: STORE_PATH, got: orders.class.name)
          return builtin_orders
        end
        orders.select { |o| o.is_a?(Hash) }.each { |o| o["state"] ||= "done" }
      else
        builtin_orders
      end
    rescue Psych::Exception, Errno::ENOENT, TypeError, NoMethodError => e
      @bus&.publish("standing_orders:load_error", error: e.message)
      builtin_orders
    end

    def builtin_orders
      BUILTIN_ORDERS.map { |o| o.transform_keys(&:to_s).merge("last_run_at" => 0, "state" => "pending") }
    end

    def persist
      return unless @orders.is_a?(Array)
      FileUtils.mkdir_p(File.dirname(STORE_PATH))
      File.write(STORE_PATH, YAML.dump(@orders))
    end
  end
end

```

## lib/master/sweep.rb
```ruby
# frozen_string_literal: true

require "open3"
require "tempfile"
require "set"
require_relative "sweep/rewriter"
require_relative "sweep/convergence"

module Master
  # Full-codebase refactor to convergence; stops on delta/oscillation/stall (arxiv:2602.21833).
  class Sweep
    MAX_CYCLES         = 16
    CONVERGE_THRESHOLD = 0.05
    CONVERGE_WINDOW    = 2
    RENAME_WINDOW    = 3
    TRAJECTORY_GAMMA = 0.9

    GLOBS = {
      rb:  "**/*.rb",
      sh:  "**/*.sh",
      yml: "**/*.yml",
      md:  "**/*.md",
      erb: "**/*.erb"
    }.freeze

    SYNTAX_CHECKERS = {
      ".rb"  => ->(p) { _, _, st = Open3.capture3("ruby", "-c", p); st.success? },
      ".sh"  => ->(p) { _, _, st = Open3.capture3("bash", "-n", p); st.success? },
      ".yml" => ->(p) { begin; Master.load_yaml(p); true; rescue StandardError => _e; false; end },
      ".erb" => ->(p) { begin; RubyVM::InstructionSequence.compile(ERB.new(File.read(p, encoding: "UTF-8")).src); true; rescue SyntaxError, StandardError => _e; false; end }
    }.freeze

    SEVERITY_RANK = Master::SEVERITY_RANK

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable|
circuit\sopen|retry\sin|llm_request)\b
    /ix.freeze

    PROMPTS_PATH      = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze
    MIN_REWRITE_BYTES = 500

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

    include Rewriter
    include Convergence

    def initialize(agent:, scanner:, root:, council: nil, event_bus: nil, code_index: nil)
      @agent      = agent
      @scanner    = scanner
      @root       = root
      @bus        = event_bus
      @code_index = code_index
      @map        = nil
      @prompts    = nil
      @rename_log = Hash.new { |h, k| h[k] = [] }
      @cycle_log  = []
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      @map            = build_codebase_map
      @prompts        = load_prompts
      violation_history = []
      converge_streak   = 0
      init_cycle_log

      max_cycles.times do |i|
        cycle       = i + 1
        changed     = 0
        cycle_viol  = 0
        cycle_fixed = 0
        cycle_defer = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, types).each do |path|
          rel    = path.delete_prefix("#{@root}/")
          before = violations_in(path)
          src    = File.read(path, encoding: "UTF-8")

          new_src, after = evaluate_rewrite(rel, src, before, cycle)
          if new_src.nil?
            cycle_defer += before
            next
          end

          delta = before - after
          File.write(path, new_src, encoding: "UTF-8")
          changed     += 1
          cycle_viol  += after
          cycle_fixed += delta
          @bus&.publish("sweep:improved", file: rel, before:, after:)
          yield cycle, rel, delta if block_given?
        end

        violation_history << cycle_viol
        entry = record_cycle(violations: cycle_viol, fixed: cycle_fixed, deferred: cycle_defer)
        @bus&.publish("sweep:cycle_stats", cycle:, **entry)
        commit("sweep: full-codebase refactor [cycle #{cycle}]") if changed > 0 && git_dirty?

        converge_streak = converged?(violation_history) ? converge_streak + 1 : 0
        break if converge_streak >= CONVERGE_WINDOW
        break if trajectory_stalled?(violation_history)
        break if should_halt_early?
      end

      summary = convergence_summary
      @bus&.publish("sweep:done", summary:)
      Result.ok(summary)
    rescue StandardError => e
      Result.err("sweep: #{e.message}", category: :unknown)
    end

    private

    def evaluate_rewrite(rel, src, before, cycle)
      new_src = rewrite(File.join(@root, rel), rel)
      return nil unless new_src && new_src.strip != src.strip && syntax_ok?(File.join(@root, rel), new_src)

      after = violations_in_text(new_src, File.join(@root, rel))
      return nil if after > before

      if rename_oscillation?(rel, src, new_src, cycle)
        @bus&.publish("sweep:oscillation_rejected", file: rel, cycle:)
        return nil
      end

      [new_src, after]
    end
  end
end

```

## lib/master/text_hygiene.rb
```ruby
# frozen_string_literal: true

module Master
  # TextHygiene — deterministic pre-write normalization.
  # Ported from MASTER2. Strips BOM, zero-width chars, CRLF, trailing spaces.
  # Called by WriteFile and StrReplace tools before writing.
  module TextHygiene
    BINARY_EXTS = %w[.png .jpg .jpeg .gif .webp .pdf .zip .gz .tgz .mp3 .mp4 .mov .woff .woff2].freeze

    module_function

    def normalize(content, filename: nil, ensure_final_newline: true)
      return content unless content.is_a?(String)

      out = content.dup
      out.gsub!("\r\n", "\n")
      out.gsub!("\r", "\n")
      out.sub!(/\A\xEF\xBB\xBF/, "")
      out.gsub!(/[\u200B\u200C\u200D\uFEFF]/, "")
      out.gsub!(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")
      out.gsub!(/[ \t]+$/, "")

      if ensure_final_newline && text_like?(filename) && !out.empty? && !out.end_with?("\n")
        out << "\n"
      end

      out
    end

    def text_like?(filename)
      return true if filename.nil?

      ext = File.extname(filename.to_s).downcase
      !BINARY_EXTS.include?(ext)
    end
  end
end

```

## lib/master/triggers.rb
```ruby
# frozen_string_literal: true

module Master
  class Triggers
    DEFAULTS       = %i[after_scan on_error budget_low tool_after].freeze
    ERROR_TRUNCATE = 200

    def initialize(event_bus:, scanner: nil, agent: nil)
      @bus     = event_bus
      @scanner = scanner
      @agent   = agent
      @rules   = []
    end

    def install_defaults!
      register(:after_scan) do |ctx|
        count = ctx[:violations].to_i
        if count > 0
          @bus.publish("triggers:violations_found", count: count)
        end
      end

      register(:on_error) do |ctx|
        @bus.publish("triggers:error_logged", error: ctx[:error].to_s[0, ERROR_TRUNCATE])
      end

      register(:budget_low) do |_ctx|
        @bus.publish("triggers:budget_low", action: "switch_to_free_tier")
      end

      @bus.subscribe("tool:after") do |ev|
        fire(:tool_after, ev)
      end

      self
    end

    def register(event, &handler)
      @rules << { event: event.to_sym, handler: handler }
    end

    def fire(event, context = {})
      matching = @rules.select { |r| r[:event] == event.to_sym }
      matching.each do |rule|
        rule[:handler].call(context)
      rescue StandardError => e
        @bus.publish("triggers:handler_error", event: event, error: e.message)
      end
    end

    def list
      @rules.map { |r| r[:event].to_s }.tally.map { |e, n| "#{e}: #{n} handler(s)" }.join("\n")
    end

    def clear!
      @rules.clear
    end
  end
end

```

## lib/master/undo.rb
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  class Undo
    MAX_JOURNAL = 50

    def initialize(session:, event_bus: nil, root: Dir.pwd)
      @session = session
      @bus     = event_bus
      @root    = root
      @journal = File.join(root, ".master", "undo_journal.jsonl")
      @stack   = load_journal
    end

    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
      @stack.shift while @stack.size > MAX_JOURNAL
      persist_journal
      Result.ok(path)
    rescue StandardError => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end

    def undo!(steps: 1)
      return Result.err("nothing to undo", category: :validation) if @stack.empty?

      steps = [steps, @stack.size].min
      paths = []

      steps.times do
        entry = @stack.pop
        restore(entry["path"], entry["content"])
        paths << entry["path"]
        @bus&.publish("undo:applied", path: paths.last)
      end

      persist_journal
      Result.ok(paths.size == 1 ? paths.first : paths)
    end

    def depth = @stack.size

    def history(limit: 10)
      @stack.last(limit).reverse.map.with_index(1) do |entry, i|
        time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
        "#{i}. #{entry["path"]} (#{time})"
      end
    end

    private

    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end
    end

    def load_journal
      return [] unless File.exist?(@journal)
      File.readlines(@journal).filter_map do |line|
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError => e
      @bus&.publish("undo:read_error", error: e.message) if defined?(@bus)
      []
    end

    def persist_journal
      FileUtils.mkdir_p(File.dirname(@journal))
      File.open(@journal, "w") do |f|
        @stack.each { |entry| f.puts(JSON.generate(entry)) }
      end
    end
  end
end

```

## lib/master/unwrap_error.rb
```ruby
# frozen_string_literal: true

module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end
end

```
