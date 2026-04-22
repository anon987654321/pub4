# 1️⃣ Clone the repo
git clone https://github.com/awesome-llm-apps/ai_email_gtm_reachout_agent.git
cd ai_email_gtm_reachout_agent

# 2️⃣ Install Ruby dependencies in an isolated bundle
bundle config set --local path 'vendor/bundle'
bundle install --jobs=$(nproc)

# 3️⃣ Export your LLM credentials (OpenRouter example)
export OPENROUTER_API_KEY=your_key_here
