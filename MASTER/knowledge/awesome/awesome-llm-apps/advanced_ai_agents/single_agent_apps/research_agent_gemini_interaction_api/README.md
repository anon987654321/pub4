# 1️⃣ Clone the repository
git clone https://github.com/yourorg/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/single_agent_apps/research_agent_gemini_interaction_api

# 2️⃣ Install Ruby dependencies (quiet output)
bundle install --quiet

# 3️⃣ Export your Gemini credentials
export GEMINI_API_KEY=your_gemini_key   # ← replace with a real key

# 4️⃣ Run the agent
ruby -r ./lib/master.rb -e "\
  Master::Agent.new.run(\
    'User Goal → Phase 1 (Plan) → Phase 2 (Research) → Phase 3 (Synthesize + Infographic)'\
  )\
"
