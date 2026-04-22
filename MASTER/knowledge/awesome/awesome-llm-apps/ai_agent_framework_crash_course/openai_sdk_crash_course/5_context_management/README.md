wrapper = RunContextWrapper.new(
  model:          RubyLLM::Providers::DeepSeek.new,      # default: deepseek‑v3 (OpenRouter)
  system_prompt: "You are a helpful AI assistant."
)
