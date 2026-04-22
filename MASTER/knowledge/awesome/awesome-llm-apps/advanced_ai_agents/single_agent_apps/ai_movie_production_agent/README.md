# Clone the upstream repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd advanced_ai_agents/single_agent_apps/ai_movie_production_agent

# Install only runtime gems (skip development & test groups)
bundle config set --local without 'development test'
bundle install --jobs=$(sysctl -n hw.ncpu) --quiet
