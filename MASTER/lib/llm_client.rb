# frozen_string_literal: true

require "ruby_llm"

module MASTER
  module LLM
    def self.configure
      RubyLLM.configure do |config|
        config.openai_api_key = ENV["OPENAI_API_KEY"]
        config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
        config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
        config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
      end
    end

    def self.chat(model: nil, **opts)
      RubyLLM.chat(model: model || default_model, **opts)
    end

    def self.default_model
      "deepseek-r1"
    end
  end
end
