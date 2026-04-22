# 1️⃣ Clone the full awesome‑llm‑apps repo
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/agent_teams/ai_vc_due_diligence_agent_team

# 2️⃣ Install Ruby dependencies (Bundler handles versions)
bundle install

# 3️⃣ Run the due‑diligence pipeline
bin/master \
  --model deepseek-ai/deepseek-v3 \
  --task "Due Diligence for Acme Corp, Series A"
