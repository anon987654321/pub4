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

    def attachment(content, filename:)
      require "ruby_llm"

      RubyLLM::Attachment.new(StringIO.new(content), filename:)
    end

    def ask(prompt, with: nil)
      require "ruby_llm"

      RubyLLM.context { |config| config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY") }
             .chat(model: @model, provider: PROVIDER, assume_model_exists: true)
             .with_params(response_format: { type: "json_object" })
             .ask(prompt, with:)
             .content
    end
  end
end
