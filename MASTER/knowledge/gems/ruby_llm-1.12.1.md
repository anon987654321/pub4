# Load the gem (Bundler automatically requires it, but you can require it manually)
require "ruby_llm"

# Build a chat client with the default configuration.
# The default model is `deepseek-ai/deepseek-v3` served through OpenRouter.
chat = RubyLLM.chat

# Send a prompt and get the model's answer.
# `ask` returns the raw content string.
# It raises on HTTP or provider errors, so you may want to rescue them.
begin
  response = chat.ask("What's the best way to learn Ruby?")
  puts response # => a textual answer from the LLM
rescue RubyLLM::Error => e
  warn "LLM request failed: #{e.class} – #{e.message}"
end