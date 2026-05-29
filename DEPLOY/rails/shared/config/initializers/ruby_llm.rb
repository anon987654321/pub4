# frozen_string_literal: true

# RubyLLM initializer — unified LLM access (OpenAI, Anthropic, Gemini, etc.)
# See WIRING_NOTES.md LLM / AI Readiness section and MASTER data/ruby_style.yml.
#
# Configure via ENV:
#   RUBY_LLM_OPENAI_API_KEY=...
#   RUBY_LLM_ANTHROPIC_API_KEY=...
#
# Usage in services/controllers:
#   chat = RubyLLM.chat
#   response = chat.ask("Summarize this post for a city feed")
#
# Tie into MASTER cognition/pipeline for council, moderation, generation, ranking.

RubyLLM.configure do |config|
  config.openai_api_key      = ENV["OPENAI_API_KEY"] || ENV["RUBY_LLM_OPENAI_API_KEY"]
  config.anthropic_api_key   = ENV["ANTHROPIC_API_KEY"] || ENV["RUBY_LLM_ANTHROPIC_API_KEY"]
  # config.gemini_api_key    = ENV["GEMINI_API_KEY"]
  # config.default_model     = "gpt-4o-mini"   # or claude-3-haiku etc.
end
