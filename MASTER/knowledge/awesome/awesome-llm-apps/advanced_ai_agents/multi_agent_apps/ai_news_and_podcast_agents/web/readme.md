# 1️⃣ Clone the repo
git clone https://github.com/yourorg/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/web

# 2️⃣ Install Ruby gems (quiet mode)
bundle install --quiet

# 3️⃣ Export runtime configuration
export MASTER_MODEL=deepseek-ai/deepseek-v3      # default LLM
export PORT=3000                                # web UI port
# export LOG_LEVEL=debug                        # optional, for verboser logs
# export MASTER_ENDPOINT=http://127.0.0.1:10002 # if Falcon runs elsewhere

# 4️⃣ Launch the Rails server
bundle exec rails server -b ${HOST:-0.0.0.0} -p $PORT
