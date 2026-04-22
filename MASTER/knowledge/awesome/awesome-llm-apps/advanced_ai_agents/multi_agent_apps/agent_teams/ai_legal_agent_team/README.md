# Clone the repository (if not already)
git clone https://github.com/your-org/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/agent_teams/ai_legal_agent_team

# Install Ruby dependencies in an isolated environment
bundle config set --local path 'vendor/bundle'
bundle install --jobs=$(nproc) --retry=3

# Verify the setup
bundle exec ruby -v
bundle exec rake test   # run the test suite to ensure everything works

# Run the legal‑agent team
bundle exec bin/master \
  --config config/legal_agent.yml \
  --model deepseek-ai/deepseek-v3 \
  --pipeline intake,infer,route,guard,execute,council,lint,memo,render

# Access the web UI (if enabled)
# The UI is served by Falcon on port 10002 and proxied via relayd at
# http://ai.brgen.no:3000
open http://ai.brgen.no:3000

# Development tips
# • Keep Ruby version aligned with .ruby-version (OpenBSD‑friendly)
# • Use `bundle exec rubocop` and `bundle exec rake test` before committing
# • Add new agents or personas under `lib/master/swarm/workers/` and update
#   `config/legal_agent.yml` accordingly.