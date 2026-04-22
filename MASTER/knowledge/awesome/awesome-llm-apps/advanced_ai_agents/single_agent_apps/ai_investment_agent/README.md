# Clone the repo (if you haven’t already)
git clone https://github.com/yourorg/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/single_agent_apps/ai_investment_agent

# Install dependencies (OpenBSD‑first)
pkg_add ruby bundler
bundle install

# Provide API credentials (DeepSeek, OpenRouter, etc.)
# Edit config.yml or set environment variables:
export DEEPSEEK_API_KEY=your_key_here
export OPENROUTER_API_KEY=your_key_here

# Run the agent on the example portfolio
ruby agent.rb data/example_portfolio.csv
