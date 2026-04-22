# Clone the repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/multi_agent_apps/agent_teams/ai_finance_agent_team

# Install Ruby dependencies (Master framework + tooling)
bundle install

# Optional: Python sandbox for the helper script
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Run the finance agent team
#   Master automatically boots the multi‑agent pipeline.
#   The default model is `deepseek-ai/deepseek-v3` (OpenRouter).
bundle exec ruby -Ilib -r master -e "Master::Agent.start"

# Access the web UI (if enabled)
#   The UI proxies through `relay` on port 3000 and forwards to Falcon 10002.
open http://ai.brgen.no:3000

# Stop the service
#   Use the rc.d service `master` or simply kill the Ruby process.
#   Example for systemctl:
#     sudo systemctl stop master
#   Or:
#     pkill -f master.rb

# Notes
# • All Ruby code lives under `lib/master/`; the framework is highly modular.
# • Configuration (model, ports, etc.) is in `lib/master/config.rb`.
# • The pipeline stages are:
#   Intake → Infer → Route → Guard → Execute → Council → Lint → Memo → Render
# • Extend or customize agents by subclassing `Master::Agent` and registering
#   new tools in `lib/master/tools/`.