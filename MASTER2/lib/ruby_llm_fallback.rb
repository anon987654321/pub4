# frozen_string_literal: true

require "ostruct"

# Offline fallback shim for environments where the ruby_llm gem is unavailable.
module RubyLLM
  FALLBACK_MODE = true
  Config = Struct.new(:openrouter_api_key)

  class << self
    def configure
      @config ||= Config.new
      yield(@config) if block_given?
      @config
    end

    def chat(model:, assume_model_exists: true, provider: nil)
      Chat.new(model: model, provider: provider)
    end

    def models
      Models.new
    end

    def moderate(_text)
      OpenStruct.new(flagged?: false)
    end

    def embed(text)
      # deterministic tiny embedding so semantic-cache callers do not crash
      bytes = text.to_s.bytes.first(8)
      OpenStruct.new(vector: bytes.map { |b| b.to_f / 255.0 })
    end
  end

  class Tool
  end

  class Models
    Model = Struct.new(:id)

    def chat_models
      [Model.new("offline/local")]
    end
  end

  class Response
    attr_reader :content, :input_tokens, :output_tokens

    def initialize(content)
      @content = content
      @input_tokens = 0
      @output_tokens = 0
    end

    def thinking
      nil
    end
  end

  class Chat
    def initialize(model:, provider: nil)
      @model = model
      @provider = provider
      @messages = []
      @params = {}
    end

    def with_params(**params)
      @params.merge!(params)
      self
    end

    def with_thinking(effort:)
      self
    end

    def with_schema(_schema)
      self
    end

    def with_instructions(_instructions)
      self
    end

    def add_message(role:, content:)
      @messages << { role: role, content: content }
      self
    end

    def ask(message)
      text = "[offline mode] #{message}"
      if block_given?
        yield OpenStruct.new(content: text)
      end
      Response.new(text)
    end
  end
end
