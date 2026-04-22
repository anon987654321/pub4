# 1️⃣ Clone the full collection (includes many agents)
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/single_agent_apps/ai_journalist_agent

# 2️⃣ Install Ruby dependencies in parallel (4 jobs by default)
bundle install --jobs 4

# 3️⃣ (Optional) Pre‑populate the symbol index – speeds up look‑ups for all agents
bundle exec ruby -Ilib -e "Master::CodeIndex.new.index!"
