# frozen_string_literal: true

return unless defined?(RubyLLM)

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"] || ENV["RUBY_LLM_OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] || ENV["RUBY_LLM_ANTHROPIC_API_KEY"]
end
