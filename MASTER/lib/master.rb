# frozen_string_literal: true

require "json"
require "timeout"
require "zeitwerk"
require "yaml"
require_relative "security_error"

# Faraday-net_http requires openssl lazily on first HTTPS call, which fails after unveil restricts dlopen paths.
begin
  require "openssl"
rescue LoadError => e
  warn "openssl: #{e.message} — LLM calls will fail"
end

unless File.respond_to?(:binary?)
  def File.binary?(path)
    return false unless File.file?(path)

    chunk = File.open(path, "rb") { |io| io.read(4096) } || ""
    chunk.include?("\x00")
  rescue StandardError
    true
  end
end

module Master
  ROOT = File.expand_path("..", __dir__).freeze
  REPO_ROOT = File.expand_path("..", ROOT).freeze
  DEPLOY_ROOT = File.join(REPO_ROOT, "DEPLOY").freeze
  DATA = File.join(ROOT, "data").freeze
  COUNCIL_PATH = File.join(DATA, "council.yml").freeze
  RULES_PATH = File.join(DATA, "rules.yml").freeze
  BOOTSTRAP_AUTHORITY_FILES = [
    ["quickstart", "QUICKSTART.md"],
    ["agents", "AGENTS.md"],
    ["soul", "data/soul.yml"],
    ["rules", "data/rules.yml"],
    ["style", "data/style.yml"],
    ["voice", "data/voice.yml"],
    ["limits", "data/limits.yml"],
    ["orders", "data/state.yml"],
    ["playbook", "data/operator_playbook.yml"],
    ["operator", "../CLAUDE.md"],
  ].freeze

  # Single source for all constitution / config data files.
  # Improves SINGULARITY and DENSITY by eliminating repeated
  # File.join(Master::ROOT, "data", ...) constructions across the codebase.
  def self.repo_root = REPO_ROOT
  def self.deploy_path(*parts) = File.join(DEPLOY_ROOT, *parts)

  def self.data_path(*parts)
    File.join(DATA, *parts)
  end

  def self.data_file(*names)
    names.each do |name|
      path = data_path(name)
      return path if File.exist?(path)
    end
    data_path(names.first)
  end

  def self.limits_path = data_file("limits.yml", "workflow.yml")
  def self.state_path = data_file("state.yml", "standing_orders.yml")
  def self.style_path = data_file("style.yml", "ruby_style.yml")

  def self.flatten_rules(body)
    case body
    when Hash then body.values.flatten
    when Array then body
    else []
    end
  end

  def self.rule_count(root: ROOT)
    flatten_rules(load_rules(root:).fetch("rules", {}))
      .count { |rule| rule.is_a?(Hash) && rule["id"].to_s.strip != "" }
  rescue StandardError
    0
  end

  def self.authority_paths(root: ROOT)
    BOOTSTRAP_AUTHORITY_FILES.filter_map do |label, rel|
      path = File.expand_path(rel, root)
      [label, path] if File.exist?(path)
    end
  end

  BUNDLE_BIN = RUBY_PLATFORM.include?("openbsd") ? "bundle34" : "bundle"
  MIN_API_KEY_LENGTH = 20
  MAX_CONSTITUTION_BYTES = 10 * 1024 * 1024
  YAML_LOAD_TIMEOUT_S = 5
  OPENROUTER_DEFAULT = "z-ai/glm-4.5-air:free"
  SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
  CTX_WINDOW_SIZE = 200_000
  VIOLATION_TRUNCATE = 90

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".yml" => "yaml", ".yaml" => "yaml",
    ".js" => "javascript", ".json" => "json", ".sh" => "bash",
    ".zsh" => "bash", ".md" => "markdown", ".html" => "html",
    ".erb" => "erb", ".css" => "css",
  }.freeze

  API_KEY_PROVIDERS = {
    anthropic_api_key: "ANTHROPIC_API_KEY",
    openai_api_key: "OPENAI_API_KEY",
    gemini_api_key: "GEMINI_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY",
    mistral_api_key: "MISTRAL_API_KEY",
    deepseek_api_key: "DEEPSEEK_API_KEY",
    xai_api_key: "XAI_API_KEY",
  }.freeze

  loader = Zeitwerk::Loader.new
  loader.push_dir(__dir__, namespace: Master)
  loader.ignore(__FILE__)
  loader.inflector.inflect(
    "cli" => "CLI",
    "llm" => "LLM",
    "llm_dispatcher" => "LLMDispatcher",
    "mcp_server" => "MCPServer",
    "mcp_coordinator" => "McpCoordinator",
    "diff_stager" => "DiffStager",
    "code_index" => "CodeIndex",
    "git_context" => "GitContext",
    "ast_edit" => "AstEdit",
    "rule_dsl" => "RuleDSL",
    "tts" => "TTS",
    "pwa_audit" => "PwaAudit",
    "mobile_pwa_operator" => "MobilePwaOperator"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.ignore(File.join(__dir__, "reach", "ruby_llm_patch.rb"))
  loader.ignore(File.join(__dir__, "reach", "bedrock_stub.rb"))
  %w[
    now/cli/signals.rb
    now/cli/command_ops.rb
    now/cli/thinking_indicator.rb
    now/command_registry/memory_commands.rb
    now/command_registry/work_commands.rb
    now/command_registry/system_commands.rb
    now/command_registry/tool_commands.rb
    judge/scan/rules/lexical_rules.rb
    judge/scan/rules/ruby_rules.rb
    judge/scan/rules/web_rules.rb
    judge/scan/rules/js_rules.rb
    judge/scan/rules/universal_rules.rb
  ].each do |rel|
    loader.ignore(File.join(__dir__, rel))
  end
  loader.ignore(File.join(__dir__, "converge.rb"))
  loader.ignore(File.join(__dir__, "converge"))
  loader.ignore(File.join(__dir__, "master_paths.rb"))
  loader.ignore(File.join(__dir__, "harness/registry.rb"))
  loader.ignore(File.join(__dir__, "history/fossils.rb"))
  loader.ignore(File.join(__dir__, "providers/catalog_index.rb"))
  loader.ignore(File.join(__dir__, "providers/fallback_chain.rb"))
  loader.ignore(File.join(__dir__, "quality/slop_budget.rb"))
  loader.ignore(File.join(__dir__, "repo/inventory.rb"))
  loader.ignore(File.join(__dir__, "scope/ledger.rb"))
  loader.ignore(File.join(__dir__, "builder/boot_phases.rb"))
  loader.ignore(File.join(__dir__, "builder/ai_boot.rb"))
  loader.ignore(File.join(__dir__, "judge/llm_dispatcher"))
  loader.setup

  require_relative "unwrap_error"
  require_relative "converge/converge"

  def self.configure_providers!
    # Stub Bedrock before ruby_llm loads — avoids openssl.so on OpenBSD/LibreSSL.
    require_relative "reach/bedrock_stub"
    require "ruby_llm"
    require_relative "reach/ruby_llm_patch"
    RubyLLM.configure do |cfg|
      API_KEY_PROVIDERS.each do |attr, env_var|
        api_key = ENV[env_var].to_s
        cfg.public_send("#{attr}=", api_key) if api_key.length >= MIN_API_KEY_LENGTH
      end
    end
    Ground::KeyRotator.configure_current!
    [Ground::ModelQuota, Trace::CacheEfficiency].each(&:name)
    Trace::CacheEfficiency.load!
  end

  def self.apply_master_loop!
    mode = ENV["MASTER_LOOP"].to_s.strip.downcase
    return if mode.empty?

    %w[MASTER_AUTOFIX MASTER_WATCH MASTER_WATCHER MASTER_HEARTBEAT MASTER_BACKGROUND].each { |flag| ENV[flag] = "0" }
    case mode
    when "fix" then ENV["MASTER_AUTOFIX"] = "1"
    when "watch" then ENV["MASTER_WATCH"] = "1"
    when "watcher" then ENV["MASTER_WATCHER"] = "1"
    when "heartbeat" then ENV["MASTER_HEARTBEAT"] = "1"
    end
  end

  def self.apply_process_defaults!
    apply_master_loop!
    return if ENV["MASTER_UNSAFE_PROCESS_DEFAULTS"] == "1"

    ENV["MASTER_SAFE_MODE"] ||= "1"
    ENV["MASTER_BACKGROUND"] ||= "0"
    ENV["MASTER_AUTOFIX"] ||= "0"
    ENV["MASTER_WATCH"] ||= "0"
    ENV["MASTER_WATCHER"] ||= "0"
    ENV["MASTER_HEARTBEAT"] ||= "0"
    ENV["MASTER_DRIFT"] ||= "0"
  end

  def self.prepare_runtime!(unsafe: false)
    ENV["MASTER_UNSAFE_PROCESS_DEFAULTS"] = "1" if unsafe
    apply_process_defaults!
    install_process_guards!
  end

  def self.runtime_catalog
    Ground::RuntimeCatalog
  end

  def self.install_process_guards!
    require_relative "ops/loop_slot"
    require_relative "ops/process_budget"
    require_relative "ops/runtime_loop_guards"
    Ops::LoopSlot.validate!
    Ops::ProcessBudget.validate_loop_slot!
    Ops::RuntimeLoopGuards.install!
  rescue LoadError => e
    warn("process_guards: #{e.message}")
  end

  def self.api_key_present?(env_var)
    ENV[env_var].to_s.length >= MIN_API_KEY_LENGTH
  end

  def self.default_model
    return "x-ai/grok-4-fast" if api_key_present?("XAI_API_KEY")
    return "x-ai/grok-4-fast" if api_key_present?("OPENROUTER_API_KEY")
    return "deepseek-chat" if api_key_present?("DEEPSEEK_API_KEY")
    return "gemini-2.5-flash" if api_key_present?("GEMINI_API_KEY")
    return "web-chat:grok" if keyless_llm_enabled?
    OPENROUTER_DEFAULT
  end

  def self.any_api_key_present?
    API_KEY_PROVIDERS.any? { |_, env_var| api_key_present?(env_var) }
  end

  def self.keyless_llm_enabled?
    return true if ENV["MASTER_KEYLESS"].to_s != ""
    return true if ENV["MASTER_WEB_CHAT"].to_s != ""
    !any_api_key_present?
  end

  def self.no_api_key_message
    if keyless_llm_enabled?
      return "No API keys configured — routing via free browser chat (web-chat:grok). " \
        "Log into grok.com, chatgpt.com, or kimi.com once in the headless profile, " \
        "or set OPENROUTER_API_KEY / XAI_API_KEY in ~/.config/master/env."
    end
    "I'm not wired to any LLM yet. Set OPENROUTER_API_KEY or XAI_API_KEY in " \
    "~/.config/master/env (or /etc/master.env on OpenBSD) and restart. " \
    "Or enable keyless mode: MASTER_KEYLESS=1 (browser chat at zero cost)."
  end

  def self.load_yaml(path, symbolize_names: false, default: {})
    raise "yaml too large: #{path}" if File.exist?(path) && File.size(path) > MAX_CONSTITUTION_BYTES

    Timeout.timeout(YAML_LOAD_TIMEOUT_S) do
      YAML.safe_load_file(path, aliases: true, symbolize_names: symbolize_names)
    end
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES => e
    warn("load_yaml: #{e.message}")
    default
  rescue Timeout::Error => e
    warn("load_yaml: #{path}: #{e.message}")
    default
  end

  def self.validate_data!(root: ROOT, bus: nil)
    @data_validation_cache ||= {}
    paths = Dir.glob(File.join(root, "data", "**/*.yml")).sort
    signature = paths.to_h { |path| [path, File.mtime(path).to_i] }
    cached = @data_validation_cache[root]
    return cached[:errors] if cached && cached[:signature] == signature

    errors = {}
    paths.each do |path|
      YAML.safe_load_file(path, aliases: true)
    rescue Psych::Exception => e
      errors[path.sub("#{root}/", "")] = e.message.lines.first.to_s.strip
    end
    @data_validation_cache[root] = { signature:, errors: }
    return errors if errors.empty?

    errors.each do |rel, msg|
      warn("yaml_validation: #{rel}: #{msg}")
      bus&.publish("data:yaml_parse_error", path: rel, error: msg)
    end
    errors
  end

  def self.load_rules(root: ROOT)
    data_dir = root == ROOT ? DATA : File.join(root, "data")
    base = load_yaml(File.join(data_dir, "rules.yml"))
    rules_dir = File.join(data_dir, "rules")
    shards = Dir.glob(File.join(rules_dir, "*.yml")).sort
    return base if shards.empty?

    merged = JSON.parse(JSON.generate(base.fetch("rules", {})))
    shards.each do |file|
      (load_yaml(file) || {}).each do |scope, list|
        (merged[scope] ||= []).concat(Array(list))
      end
    end
    base.merge("rules" => merged)
  end

  def self.const_missing(sym)
    return Judge::Agent if sym == :Agent
  end

  def self.build(root: Dir.pwd)
    ENV["MASTER_SCAN_ONLY"] == "1" ? Builder.build_scan_only(root:) : Builder.build(root:)
  end

  def self.start_constitution_drift(container)
    return unless ENV["MASTER_DRIFT"] == "1"

    Thread.new do
      Ground::Orders::ConstitutionDrift.new(container:).call
    rescue StandardError => e
      warn("constitution_drift: #{e.message}")
    end
  end

  def self.bootstrap_container(root: Dir.pwd)
    prepare_runtime!
    init_ground(root:)
    container = init_judge(root:)
    init_loop(root:, container:)
    init_reach(container:)
  end

  def self.init_ground(root:)
    Trace::Telemetry.bootstrap!(root: root)
    Ground::GitHooks.ensure_pre_commit!(root: root)
  end

  def self.init_judge(root:)
    Builder.build(root:)
  end

  def self.init_loop(root:, container:)
    validate_data!(root: root, bus: container[:bus])
    Builder.boot_snapshot(container)
    container[:heartbeat]&.start!
  end

  def self.init_reach(container:)
    start_constitution_drift(container)
    container
  end

  def self.ensure_services!(root: ROOT)
    return if ENV["MASTER_SKIP_TTS"] == "1"

    Voice::TtsSupervisor.ensure_daemon!(root: root)
  end

  def self.boot(root: Dir.pwd)
    return boot_fast(root:) if ENV["MASTER_FAST"] == "1"

    prepare_runtime!
    Ground::Pledge.stage1_boot!(root)
    ensure_services!(root: root)
    container = bootstrap_container(root: root)
    Ground::Pledge.stage2_lock!
    Now::CLI.new(container:)
  end

  def self.boot_fast(root: Dir.pwd)
    prepare_runtime!
    container = Builder.build_fast(root:)
    Now::CLI.new(container:)
  end
end
