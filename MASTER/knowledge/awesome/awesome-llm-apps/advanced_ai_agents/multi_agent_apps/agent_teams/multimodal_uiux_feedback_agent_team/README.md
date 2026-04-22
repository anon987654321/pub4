# 1️⃣ Clone the example repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/agent_teams/multimodal_uiux_feedback_agent_team

# 2️⃣ Install runtime dependencies only
bundle config set --local without 'development test'
bundle install --jobs=$(sysctl -n hw.ncpu)

# 3️⃣ Export your OpenRouter key (required by the default DeepSeek model)
export OPENROUTER_API_KEY=your_key_here

# 4️⃣ Run the pipeline
bundle exec ruby -Ilib bin/master run \
  --pipeline intake,infer,route,guard,execute,council,lint,memo,render \
  --stage render
