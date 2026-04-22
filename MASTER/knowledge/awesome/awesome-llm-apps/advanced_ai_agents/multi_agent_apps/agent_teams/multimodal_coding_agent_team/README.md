# 1. Clone the repository
git clone https://github.com/yourorg/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/agent_teams/multimodal_coding_agent_team

# 2. Install Ruby dependencies
bundle install --jobs=$(sysctl -n hw.ncpu) --retry=3

# 3. Prepare the knowledge base (optional but recommended)
#    This indexes the current codebase for fast symbol lookup.
bundle exec ruby -Ilib -e "require 'master/code_index'; Master::CodeIndex.new.refresh!"

# 4. (Web UI) Set up the Rails server
bundle exec rails db:setup
bundle exec rails assets:precompile
