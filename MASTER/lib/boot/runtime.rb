# frozen_string_literal: true

module Master
  # Provider selection, model limits, and safe process defaults for Master.*.
  module MasterRuntime
    PROCESS_DEFAULTS = {
      "MASTER_SAFE_MODE" => "1", "MASTER_BACKGROUND" => "0", "MASTER_AUTOFIX" => "0",
      "MASTER_WATCH" => "0", "MASTER_WATCHER" => "0", "MASTER_HEARTBEAT" => "0", "MASTER_DRIFT" => "0",
    }.freeze
    # MASTER_LOOP selects one loop by mode name. The name->env mapping is the one
    # source in data/limits.yml#process (Ops::ProcessBudget.env_by_loop); "fix" is the
    # historical alias for the "autofix" loop. Kept explicit here because it is read
    # at early boot; test_master_loop pins it to process.yml so the two cannot drift.
    LOOP_FLAGS = {
      "fix" => "MASTER_AUTOFIX", "watch" => "MASTER_WATCH",
      "watcher" => "MASTER_WATCHER", "heartbeat" => "MASTER_HEARTBEAT",
    }.freeze

    def configure_providers!
      require_relative "../io/bedrock_stub"
      require "ruby_llm"
      require_relative "../io/ruby_llm_patch"
      RubyLLM.configure { |config| apply_api_keys(config) }
      Ground::KeyRotator.configure_current!
      [Ground::ModelQuota, Trace::CacheEfficiency].each(&:name)
      Trace::CacheEfficiency.load!
    end

    def apply_master_loop!
      mode = ENV["MASTER_LOOP"].to_s.strip.downcase
      return if mode.empty?

      LOOP_FLAGS.values.each { |flag| ENV[flag] = "0" }
      ENV[LOOP_FLAGS[mode]] = "1" if LOOP_FLAGS.key?(mode)
    end

    def apply_process_defaults!
      apply_master_loop!
      return if ENV["MASTER_UNSAFE_PROCESS_DEFAULTS"] == "1"

      PROCESS_DEFAULTS.each { |key, value| ENV[key] ||= value }
    end

    def prepare_runtime!(unsafe: false)
      ENV["MASTER_UNSAFE_PROCESS_DEFAULTS"] = "1" if unsafe
      require_relative "../ground/env_loader"
      Ground::EnvLoader.load!
      apply_process_defaults!
      require_relative "../ground/host_budget"
      Ground::HostBudget.apply_defaults!
      install_process_guards!
    end

    def runtime_catalog = Ground::RuntimeCatalog

    def install_process_guards!
      require_relative "../ops/loop_slot"
      require_relative "../ops/process_budget"
      require_relative "../ops/runtime_loop_guards"
      Ops::LoopSlot.validate!
      Ops::ProcessBudget.validate_loop_slot!
      Ops::RuntimeLoopGuards.install!
    rescue LoadError => e
      warn("process_guards: #{e.message}")
    end

    def provider_config(root: ROOT) = load_yaml(File.join(root, "data", "providers.yml"))

    # One source for the OpenRouter default: providers.yml openrouter.default_model.
    # It lived three times — a Master constant, providers.yml, soul negotiable —
    # and the 2026-08-18 registry fix had to hand-edit all three in step. The
    # next withdrawn-slug swap is one yml line.
    def openrouter_default(root: ROOT)
      @openrouter_default ||= provider_config(root:).dig("openrouter", "default_model")
    end

    # Head of models.grok_primary — the declared :free pool this runtime routes
    # first when an OpenRouter key is present.
    def free_primary_model(root: ROOT)
      @free_primary_model ||= load_yaml(File.join(root, "data", "models.yml"))
                              .dig("models", "grok_primary")&.first&.fetch("id")
    end

    def api_key_specs(root: ROOT)
      provider_config(root:).flat_map { |_name, config| provider_key_specs(config) }.compact
    end

    def api_key_present?(env_var, root: ROOT)
      spec = api_key_specs(root:).find { |_attr, candidate, _minimum| candidate == env_var }
      minimum = spec ? spec.last : MIN_API_KEY_LENGTH_HEURISTIC
      ENV[env_var].to_s.length >= minimum
    end

    def agy_cli_available?
      return false if ENV["MASTER_NO_AGY_CLI"] == "1"
      return true if ENV["AGY_BIN"] && File.file?(ENV["AGY_BIN"]) && File.executable?(ENV["AGY_BIN"])

      home_bin = File.expand_path("~/.local/bin/agy")
      return true if File.file?(home_bin) && File.executable?(home_bin)

      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
        exe = File.join(dir, "agy")
        File.file?(exe) && File.executable?(exe)
      end
    end

    def default_model
      return "agy:auto" if agy_cli_available?
      return "grok-4.3" if api_key_present?("XAI_API_KEY") && !api_key_present?("OPENROUTER_API_KEY")
      return free_primary_model if api_key_present?("OPENROUTER_API_KEY")
      return "deepseek-chat" if api_key_present?("DEEPSEEK_API_KEY")
      return "gemini-2.5-flash" if api_key_present?("GOOGLE_API_KEY") || api_key_present?("GEMINI_API_KEY")
      return "web-chat:grok" if keyless_llm_enabled?

      openrouter_default
    end

    def any_api_key_present?
      return true if agy_cli_available?

      api_key_specs.any? { |_attr, env_var, minimum| ENV[env_var].to_s.length >= minimum }
    end

    def context_window(model = nil, root: ROOT)
      entry = provider_models(root:).values.find do |candidate|
        candidate.is_a?(Hash) && candidate["id"].to_s == model.to_s
      end
      (entry&.fetch("context_window", nil) || DEFAULT_CONTEXT_WINDOW).to_i
    end

    def provider_models(root: ROOT)
      load_yaml(File.join(root, "data", "models.yml")).fetch("model_defs", {})
    end

    def keyless_llm_enabled?
      ENV["MASTER_KEYLESS"].to_s != "" || ENV["MASTER_WEB_CHAT"].to_s != "" || !any_api_key_present?
    end

    def no_api_key_message
      return keyless_message if keyless_llm_enabled?

      "I'm not wired to any LLM yet. Install Antigravity CLI (agy) or set OPENROUTER_API_KEY / XAI_API_KEY in " \
        "~/.config/master/env (or /etc/master.env on OpenBSD) and restart. " \
        "Or enable keyless mode: MASTER_KEYLESS=1 (browser chat at zero cost)."
    end

    private

    def apply_api_keys(config)
      api_key_specs.each do |attribute, env_var, minimum|
        setter = "#{attribute}="
        next unless config.respond_to?(setter)

        key = ENV[env_var].to_s
        config.public_send(setter, key) if key.length >= minimum
      end
    end

    def provider_key_specs(config)
      return [] unless config.is_a?(Hash) && config["ruby_llm_key"]

      minimum = config.fetch("min_key_length", MIN_API_KEY_LENGTH_HEURISTIC).to_i
      Array(config["env"]).map { |env_var| [config["ruby_llm_key"].to_sym, env_var, minimum] }
    end

    def keyless_message
      "No API keys configured — routing via free browser chat (web-chat:grok). " \
        "Set OPENROUTER_API_KEY / XAI_API_KEY in ~/.config/master/env for API routing."
    end
  end
end
