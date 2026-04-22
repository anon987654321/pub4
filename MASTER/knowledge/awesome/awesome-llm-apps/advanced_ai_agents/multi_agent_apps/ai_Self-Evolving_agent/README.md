# 1️⃣ Clone the repo
git clone https://github.com/yourorg/ai-self-evolving-agent.git
cd ai-self-evolving-agent

# 2️⃣ Install runtime gems only
bundle config set --local without 'development test'
bundle install --jobs=$(sysctl -n hw.ncpu 2>/dev/null || nproc)

# 3️⃣ Start the master daemon (default DeepSeek model)
bundle exec ruby -Ilib bin/master

# 4️⃣ Open the web UI
open http://ai.brgen.no:3000   # or http://localhost:3000 on your machine
