# Clone the starter collection
git clone https://github.com/awesome-llm-apps/starter_ai_agents.git
cd starter_ai_agents/web_scrapping_ai_agent

# Install dependencies (OpenBSD‑friendly)
bundle config set --local without 'development test'
bundle install

# Run the agent (default model: deepseek‑v3 on OpenRouter)
bundle exec ruby web_scrapping_ai_agent.rb
