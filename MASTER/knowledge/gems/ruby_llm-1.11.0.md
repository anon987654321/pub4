# frozen_string_literal: true

require "ruby_llm"

# Configure a chat client.
# • `model` – the LLM to use; defaults to the deepseek‑v3 model.
# • `temperature` – low (0.1) for deterministic output.
# • `max_tokens` – safety ceiling.
chat = RubyLLM.chat(
  model:       "deepseek-ai/deepseek-v3",
  temperature: 0.1,
  max_tokens:  512
)

# System prompt that guides the model’s tone and expertise.
chat.system "You are a concise, expert Ruby mentor."

begin
  # Ask the model a question and print the response.
  answer = chat.ask("What’s the best way to learn Ruby?")
  puts answer
rescue RubyLLM::Error => e
  # All LLM‑related errors inherit from RubyLLM::Error.
  warn "LLM error: #{e.class} – #{e.message}"
  exit 1
end
