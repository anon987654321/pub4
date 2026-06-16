# Load the library (Rails apps load it automatically)
require "ruby_llm"

# Create a chat client using the default provider (DeepSeek via OpenRouter)
chat = RubyLLM.chat

# Send a single‑turn prompt
response = chat.ask("What’s the best way to learn Ruby?")

# The API returns a plain‑text string; you can also access the full
# `RubyLLM::Content::Raw` object for metadata.
puts response
