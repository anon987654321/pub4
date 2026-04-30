# frozen_string_literal: true

require "zeitwerk"

module Master
  ROOT = File.expand_path("..", __dir__).freeze

  MIN_API_KEY_LENGTH = 20
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
    openrouter_api_key: "OPENROUTER_API_KEY"
  }.freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "autoloop" => "AutoLoop",
    "cli"      => "CLI",
    "llm"      => "LLM"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.ignore(File.join(__dir__, "master", "ruby_llm_patch.rb"))
  # Ignore SRP extraction files that reopen their parent module rather than defining a new constant.
  # Zeitwerk expects file base_name -> constant, but these files add methods to an existing module.
  %w[
    autoloop/fix_evaluator.rb
    builder/infra_helpers.rb
    cli/signals.rb
    cli/tts.rb
    command_registry/agent_commands.rb
    command_registry/memory_commands.rb
    command_registry/service_commands.rb
    memory/search.rb
    sweep/rewriter.rb
    sweep/convergence.rb
  ].each do |rel|
    loader.ignore(File.join(__dir__, "master", rel))
  end
  loader.setup

  def self.configure_providers!
    require "ruby_llm"
    require_relative "master/ruby_llm_patch"
    RubyLLM.configure do |cfg|
      API_KEY_PROVIDERS.each do |attr, env_var|
        val = ENV[env_var].to_s
        cfg.public_send("#{attr}=", val) if val.length >= MIN_API_KEY_LENGTH
      end
    end
  end

  def self.api_key_present?(env_var)
    ENV[env_var].to_s.length >= MIN_API_KEY_LENGTH
  end

  def self.default_model
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("OPENROUTER_API_KEY")
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("REPLICATE_API_KEY")
    return "claude-sonnet-4-6" if api_key_present?("ANTHROPIC_API_KEY")
    return "gpt-4o" if api_key_present?("OPENAI_API_KEY")
    return "gemini-2.5-flash" if api_key_present?("GEMINI_API_KEY")
    raise "No LLM API key found. Set OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY."
  end

  def self.load_yaml(path)
    YAML.safe_load_file(path, aliases: true)
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES => e
    warn("load_yaml: " + e.message)
    {}
  end

  def self.build(root: Dir.pwd)
    Builder.build(root:)
  end

  def self.boot(root: Dir.pwd, argv: [])
    Pledge.stage1_boot!(root)
    container = Builder.build(root:)
    Builder.boot_snapshot(container)
    container[:heartbeat]&.start!
    Pledge.stage2_lock!
    CLI.new(container:)
  end
end
