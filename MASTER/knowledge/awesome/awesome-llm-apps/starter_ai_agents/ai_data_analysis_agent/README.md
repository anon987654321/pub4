# Clone the full Awesome‑LLM‑Apps monorepo
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/starter_ai_agents/ai_data_analysis_agent

# Install Ruby dependencies (OpenBSD‑friendly)
bundle config set --local without 'development test'
bundle install --jobs=$(sysctl -n hw.ncpu)

# Set the LLM provider (default: DeepSeek via OpenRouter)
export MASTER_MODEL=deepseek-ai/deepseek-v3
# Optional: configure API keys
export OPENROUTER_API_KEY=your_key_here

# Start the agent (Web UI on http://localhost:3000)
bin/master start

# Or run a single analysis task from the CLI
bin/master run data_analysis \
  --input data/sample.csv \
  --output results/analysis.md
