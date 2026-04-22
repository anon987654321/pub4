# Add the tools to your Gemfile
gem 'master', path: 'lib/master'   # or the appropriate source

# Install dependencies
bundle install

# Load the LLM optimisation toolbox in your Ruby script
require 'master/tools/llm'

# -------------------------------------------------
# ✨ What the toolbox does
# -------------------------------------------------
# `Master::Tools::LLM` is a thin, opinionated wrapper around a
# language‑model inference endpoint.  It is designed to
#   * batch‑process large textual assets (CSV, JSON, plain‑text) and
#   * rewrite them so they fit inside the model’s context window.
#
# Features
# • Automatic chunking to stay within `max_tokens`
# • Built‑in retry + circuit‑breaker handling
# • Returns a `Master::Result` (Ok/Err) for predictable error flow
# • Extensible – swap the model or inject a custom client

# -------------------------------------------------
# 🛠️ Example: optimise a CSV with DeepSeek‑v3
# -------------------------------------------------
optimizer = Master::Tools::LLM.new(
  model:        'deepseek-ai/deepseek-v3', # OpenRouter identifier
  max_tokens:   2_048,                    # Model‑specific context limit
  temperature:  0.0,                      # Deterministic output
  retries:      2                         # Automatic retry count
)

# Optimise a single file.  The method returns a Result monad:
#   Master::Result::Ok   → payload ready for inference
#   Master::Result::Err  → error object with diagnostics
result = optimizer.optimize_file('data/large_dataset.csv')

if result.ok?
  puts result.value # → Optimised payload ready for LLM inference
else
  warn "Optimization failed: #{result.error.message}"
end

# -------------------------------------------------
# 📚 Advanced usage
# -------------------------------------------------
# • **Custom chunk size** – adjust `max_tokens` to match your model.
# • **Streaming** – call `optimize_stream` to process data lazily.
# • **Multiple files** – iterate `optimize_file` or use `optimize_dir`.
# • **Tool integration** – combine with `Master::Tools::WriteFile` to
#   persist the optimiser’s output.
# • **Error handling** – inspect `result.error` for `Master::UnwrapError`,
#   circuit‑breaker state, or HTTP status codes.

# -------------------------------------------------
# 🧭 Where to go next
# -------------------------------------------------
# • Read the source at `lib/master/tools/llm.rb` for the full API.
# • Inspect `Master::Tools::LLM::DEFAULTS` for every configurable knob.
# • Pair with `Master::Tools::GitContext` to version‑control optimisation artefacts.
# • Use `Master::Tools::SymbolLookup` to locate model‑specific symbols in your
#   codebase before optimisation.