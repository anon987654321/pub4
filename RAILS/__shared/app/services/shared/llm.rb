# frozen_string_literal: true

require "stringio"

module Shared
  class Llm
    DEFAULT_MODEL = "google/gemini-2.0-flash-001"
    PROVIDER = :openrouter
    PROVIDER_KEY_ENVS = {
      openrouter: "OPENROUTER_API_KEY",
      groq: "GROQ_API_KEY",
    }.freeze
    GROQ_API_BASE = "https://api.groq.com/openai/v1"

    def self.key_env_for(provider)
      PROVIDER_KEY_ENVS.fetch(provider.to_sym)
    end

    def self.configured?(provider: PROVIDER, key_env: nil)
      ENV[key_env || key_env_for(provider)].to_s.strip != ""
    end

    def initialize(model: DEFAULT_MODEL, provider: PROVIDER, key_env: nil)
      @model = model
      @provider = provider.to_sym
      @key_env = key_env || self.class.key_env_for(@provider)
    end

    # json=true keeps the existing structured-output contract; plain responses
    # opt out so streaming and prose callers share this provider boundary too.
    def ask(prompt, with: nil, json: true, &block)
      require "ruby_llm"

      chat = RubyLLM.context { |config| configure_provider(config) }
                         .chat(model: model_for_ruby_llm, provider: ruby_provider, protocol: :chat_completions, assume_model_exists: true)
      chat = chat.with_provider_options(response_format: { type: "json_object" }) if json

      response = chat.ask(prompt, with:, &block)
      response.content
    end

    def attachment(content, filename:)
      require "ruby_llm"

      RubyLLM::Attachment.new(StringIO.new(content), filename:)
    end

    private

    def configure_provider(config)
      # RubyLLM's defaults (300s open timeout, 3 retries) are tuned for long
      # completions, not for the JSON classification calls everything here
      # makes. Untuned, one hung OpenRouter connection pins a Falcon fibre for
      # minutes — on a synchronous server that is lost capacity, and amber's
      # AI endpoints are synchronous. 30s and one retry bound a call to about
      # a minute worst case; LLM_REQUEST_TIMEOUT lets the operator tune it
      # without a deploy.
      config.request_timeout = ENV.fetch("LLM_REQUEST_TIMEOUT", "30").to_i
      config.max_retries = 1

      case @provider
      when :openrouter
        config.openrouter_api_key = ENV.fetch(@key_env)
      when :groq
        config.openai_api_key = ENV.fetch(@key_env)
        config.openai_api_base = GROQ_API_BASE
      else
        raise KeyError, "unsupported LLM provider: #{@provider.inspect}"
      end
    end

    def ruby_provider
      @provider == :groq ? :openai : @provider
    end

    def model_for_ruby_llm
      @provider == :groq ? @model.delete_prefix("groq/") : @model
    end
  end
end
