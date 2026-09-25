# frozen_string_literal: true

require "stringio"

module Shared
  class Llm
    DEFAULT_MODEL = "google/gemini-2.0-flash-001"
    PROVIDER = :openrouter

    def self.configured?
      ENV["OPENROUTER_API_KEY"].to_s.strip != ""
    end

    def initialize(model: DEFAULT_MODEL)
      @model = model
    end

    # json=true keeps the existing structured-output contract; plain responses
    # opt out so streaming and prose callers share this provider boundary too.
    def ask(prompt, with: nil, json: true, &block)
      require "ruby_llm"

      chat = RubyLLM.context { |config| config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY") }
                         .chat(model: @model, provider: PROVIDER, assume_model_exists: true)
      chat = chat.with_params(response_format: { type: "json_object" }) if json

      response = chat.ask(prompt, with:, &block)
      response.content
    end

    def attachment(content, filename:)
      require "ruby_llm"

      RubyLLM::Attachment.new(StringIO.new(content), filename:)
    end
  end
end
