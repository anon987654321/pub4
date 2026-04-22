# Clone the repository (the README lives under the path shown)
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_mental_wellbeing_agent

# Install the exact gem versions pinned in Gemfile.lock
bundle config set --local without 'development test'
bundle install --jobs=$(nproc) --retry=3
