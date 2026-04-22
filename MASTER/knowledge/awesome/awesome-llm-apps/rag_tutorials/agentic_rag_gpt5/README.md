# 1️⃣ Clone the repository
git clone https://github.com/your-org/awesome-llm-apps.git
cd awesome-llm-apps/rag_tutorials/agentic_rag_gpt5

# 2️⃣ Install Ruby dependencies (uses bundler and the OpenBSD‑friendly Ruby)
bundle config set --local without 'development test'
bundle install --jobs=$(nproc) --retry=3

# 3️⃣ Provide your OpenRouter API key
export OPENROUTER_API_KEY=sk_XXXXXXXXXXXXXXXXXXXX

# 4️⃣ (Optional) Adjust model or temperature
#    Edit lib/master/config.rb → DEFAULT_MODEL / DEFAULT_TEMPERATURE

# 5️⃣ Run the demo
ruby -Ilib bin/master run
