# 1️⃣ Shallow clone – keeps history tiny
git clone --depth 1 https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/voice_ai_agents/ai_audio_tour_agent

# 2️⃣ Install dependencies in an isolated bundle
bundle config set --local path vendor/bundle
bundle install --quiet

# 3️⃣ Provide your LLM API key (OpenRouter, DeepSeek, etc.)
export OPENROUTER_API_KEY=your-key-here

# 4️⃣ Run the tour (uses default audio devices)
ruby run_tour.rb
