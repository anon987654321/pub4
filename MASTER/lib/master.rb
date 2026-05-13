# frozen_string_literal: true

require "zeitwerk"
require "yaml"

# Pre-load openssl before pledge stage1 engages — faraday-net_http requires it
# lazily on first HTTPS call, which fails after unveil restricts dlopen paths.
begin
  require "openssl"
rescue LoadError => e
  warn "openssl: #{e.message} — LLM calls will fail"
end

module Master
  ROOT = File.expand_path("..", __dir__).freeze

  MIN_API_KEY_LENGTH = 20
  SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
  CTX_WINDOW_SIZE = 200_000
  VIOLATION_TRUNCATE = 90

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".yml" => "yaml", ".yaml" => "yaml",
    ".js" => "javascript", ".json" => "json", ".sh" => "bash",
    ".zsh" => "bash", ".md" => "markdown", ".html" => "html",
    ".erb" => "erb", ".css" => "css"
  }.freeze

  API_KEY_PROVIDERS = {
    anthropic_api_key:  "ANTHROPIC_API_KEY",
    openai_api_key:     "OPENAI_API_KEY",
    gemini_api_key:     "GEMINI_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY",
    mistral_api_key:    "MISTRAL_API_KEY",
    deepseek_api_key:   "DEEPSEEK_API_KEY"
  }.freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "cli"            => "CLI",
    "llm"            => "LLM",
    "llm_dispatcher" => "LLMDispatcher"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.ignore(File.join(__dir__, "master", "ruby_llm_patch.rb"))
  %w[
    loop/auto_loop/fix_evaluator.rb
    builder/infra_helpers.rb
    now/cli/signals.rb
    command_registry/agent_commands.rb
    command_registry/memory_commands.rb
    command_registry/service_commands.rb
    memory/search.rb
    loop/sweep/rewriter.rb
    loop/sweep/convergence.rb
  ].each do |rel|
    loader.ignore(File.join(__dir__, "master", rel))
  end
  loader.setup

  def self.configure_providers!
    # Stub Bedrock before ruby_llm loads — avoids openssl.so on OpenBSD/LibreSSL.
    # MASTER only uses OpenRouter; Bedrock is never needed.
    require_relative "master/bedrock_stub"
    require "ruby_llm"
    require_relative "master/ruby_llm_patch"
    RubyLLM.configure do |cfg|
      API_KEY_PROVIDERS.each do |attr, env_var|
        api_key = ENV[env_var].to_s
        cfg.public_send("#{attr}=", api_key) if api_key.length >= MIN_API_KEY_LENGTH
      end
    end
  end

  def self.api_key_present?(env_var)
    ENV[env_var].to_s.length >= MIN_API_KEY_LENGTH
  end

  def self.default_model
    return "deepseek-chat" if api_key_present?("DEEPSEEK_API_KEY")
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("OPENROUTER_API_KEY")
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("REPLICATE_API_KEY")
    return "claude-sonnet-4-6" if api_key_present?("ANTHROPIC_API_KEY")
    return "gpt-4o" if api_key_present?("OPENAI_API_KEY")
    return "gemini-2.5-flash" if api_key_present?("GEMINI_API_KEY")
    return "mistral-large-latest" if api_key_present?("MISTRAL_API_KEY")
    raise "No LLM API key found. Set DEEPSEEK_API_KEY, OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, or MISTRAL_API_KEY."
  end

  def self.load_yaml(path, symbolize_names: false, default: {})
    YAML.safe_load_file(path, aliases: true, symbolize_names: symbolize_names)
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES => e
    warn("load_yaml: " + e.message)
    default
  end

  def self.build(root: Dir.pwd)
    Builder.build(root:)
  end

  def self.bootstrap_container(root: Dir.pwd)
    Trace::Telemetry.bootstrap!(root: root)
    container = Builder.build(root:)
    Builder.boot_snapshot(container)
    container[:heartbeat]&.start!
    container
  end

  def self.boot(root: Dir.pwd)
    Pledge.stage1_boot!(root)
    container = bootstrap_container(root: root)
    Pledge.stage2_lock!
    Now::CLI.new(container:)
  end
end
