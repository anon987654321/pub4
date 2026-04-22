# 1️⃣ Clone the demo repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/mcp-github-agent

# 2️⃣ Install production dependencies only
bundle config set --local without 'development test'
bundle install --jobs=4
